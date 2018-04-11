#!/usr/bin/perl -w
#
#  Open a serial port and perform read/write commands using
#    Emerson SCC Machine to Machine protocol
#

use POSIX ;

our $debug ;

my $serialdev = shift @ARGV  || die "usage: $0 /path/to/serial [cmds]" ;
sysopen( SCC, $serialdev, O_NONBLOCK|O_RDWR ) or die "Unable to open $0: $!" ;

# Configure the serial port
my $termios = POSIX::Termios->new ;
my $saved_tio = POSIX::Termios->new ;
$termios->getattr( fileno(SCC) );
$saved_tio = $termios ;  # Save for later restore
$termios->setospeed( B9600 );
$termios->setispeed( B9600 );
# Configure flags.  This should be mostly RAW, but with some CR/NL handling
$termios->setiflag( $termios->getiflag
      # Clear these flags
      & ~(  IGNBRK | BRKINT | 
            IGNPAR | PARMRK | INPCK | ISTRIP |
            INLCR | IGNCR |
            IXON | IXOFF )
      # Set these flags
      | ( ICRNL )
   );
$termios->setlflag( $termios->getlflag
      # Clear these flags
      & ~( ICANON | ISIG)
   );
$termios->setoflag( $termios->getoflag
      # Clear these flags
      & ~( OPOST )
   );

# Apply the new settings immediately
$termios->setattr( fileno(SCC), &POSIX::TCSANOW );

### sysreadt(): Read with a timeout for a non-blocking FH
### $length = sysreadt(FH,$readbuf,$length,$timeout)
###    If $length < 0, read until '\n' received or timeout
sub sysreadt (*$$$) {
   my ($handle, undef, $length, $timeout) = @_ ;
#print "length = $length, timeout = $timeout\n" ;
   my $readbuf = "";
   my $endtime = time( ) + $timeout ;
   my $rfd = "" ;
   vec( $rfd, fileno($handle), 1 ) = 1 ;

RETRY: until( time( ) >= $endtime ) {
      # try to fill the requested data
      my $tlen = 1;
      if( $length > 1 ) {
         $tlen = $length - length($readbuf) ;
         if( $tlen < 0 ) { $tlen = 0; };
      };
      # Assume it's non-blocking
      $tlen = sysread( $handle, $readbuf, $tlen, length($readbuf) );
#print "sysread returns ", $tlen || "undef", " ($!)  readbuf >$readbuf<\n" ;
      # If we want more data
      if( $length > 0 && length($readbuf) < $length
            || $length < 0 && $readbuf !~ m/\n\z/ ) {
         # And we got some
         if( defined($tlen) && $tlen > 0 ) {  # $tlen undef if no data
            # Get more immediately
#print "getting more immediately\n" ;
            next RETRY ;
         } else {
            # Wait for it
            my ( $rdyfd, $errfd );
#print "calling select at ", scalar( time() ), "...\n" ;
            select( $rdyfd=$rfd, undef, $errfd=$rfd, $endtime - time() + 0.1 );
            # TODO: Verify $rdyfd or $errfd have fileno($handle) set
#print "select returns at ", scalar( time() ), "...\n" ;
         };
      } else {
         # We're done
#print "we're done !\n" ;
         last RETRY ;
      };
   };

   $_[1] = $readbuf ;
   return length($readbuf);
}

### Calculate a checksum word for a message
sub msgchk ($) {
   my $msg = shift ;
   $msg =~ s/^~// ;  # Strip leading ~ if found
   if( (length( $msg ) & 1) != 0 ) { warn "Odd message: $msg" };
   # This would have made more sense, but it's not right.
   # Convert hex pairs (high nibble first) to an array of numbers
   # my @msg = map { ord() } split( "", pack( "H*", $msg ));
   ### OMG, they checksum the ASCII characters?!? and then transmit
   ### the checksum as HEX ASCII...
   my @msg = map { ord() } split( "", $msg );
   if( $debug ) { print "Message: ", join(":", @msg), "\n" };
   # Sum all the numbers
   my $msgsum = 0 ;
   for my $v ( @msg ) { $msgsum += $v };
   # Two's complement and truncate to 16 bit big-endian (network) number
   #    then convert to hex
   my $sum = unpack( "H*", pack( "n", (~$msgsum +1) & 0xFFFF ) );

   return toupper($sum) ;
}

# Registers *without* prefix or checksums
#       Prefix:  ~2001E1EBA006 (to read)
#                ~2001E1EC200E (to write)
#       Checksum: see msgchk()
our %regmap = (
      dhcp => "000E65",
      link => "000E6E",
      ip   => "meta:ip1:ip2:ip3:ip4",
      ip1  => "000C52", ip2  => "000C53", ip3  => "000C54", ip4  => "000C55",
      gw   => "meta:gw1:gw2:gw3:gw4",
      gw1  => "000C58", gw2  => "000C59", gw3  => "000C5A", gw4  => "000C5B",
      sm   => "meta:sm1:sm2:sm3:sm4",
      sm1  => "000C5E", sm2  => "000C5F", sm3  => "000C60", sm4  => "000C61",
      tp   => "meta:tp1:tp2:tp3:tp4",
      trap => "meta:tp1:tp2:tp3:tp4",
      tp1  => "000C6A", tp2  => "000C6B", tp3  => "000C6C", tp4  => "000C6D",

      outmV => "010110", outVnv => "0100A4",
      numRect => "000E6B",
      numRedRect => "000E6C",
      numBBU => "000E6D",
   );

our %labels = (
      dhcp => "DHCP",
      link => "LINK",
      ip   => "IP",
      gw   => "GW",
      sm   => "SM",
      tp   => "TRAP",
      trap => "TRAP",
      outmV => "Vout",
      outVnv => "Vout(NV)",
      numRect => "Rect",
      numRedRect => "N+R",
      numBBU => "BBU",
   );


sub getreg {
   my $regname = shift ;

   return undef  unless defined($regmap{$regname}) ;

   my $reg = $regmap{$regname} ;

   if( $reg =~ /^meta:/ ) {
      # meta register, recurse to collect all the sub-values
      my @subreg = split /:/, $reg ;
      return join ".", map { getreg($_) } @subreg[1..$#subreg];
   };

   my $msg = "~2001E1EBA006".$reg ;
   my $reply = "" ;
   syswrite( SCC, $msg.msgchk($msg)."\r" );
   sysreadt( SCC, $reply, -1, 10 );
   chomp $reply ;
   # expect: ~2001E100800800000000FC17
   # answer is here:      ^^^^^^^^
   # Verify reply and checksum
   if( $reply !~ /^~2001E1008008/
         || msgchk(substr($reply,0,-4)) ne substr($reply,-4) ) {
      print "WARNING: Unexpected response\nReceived: $reply\nExpected: ~2001E1008008<><><><>", msgchk(substr($reply,0,-4)), "\n" ;
      return undef ;
   }

   if( $reg =~ /^01/ ) {
      # Unpack a 32-bit little-endian floating point value
      return unpack("f<",pack("H*",substr($reply,13,8))) ;
   } elsif( $reg =~ /^00/ ) {
      # 32-bit value (expected desired value in first byte)
      return unpack("V",pack("H*",substr($reply,13,8))) ;
   } else {
      warn "Unrecognized type in register: $reg" ;
      return substr($reply,13,8);
   }
};

### setreg()  To set a register
sub setreg {
   my $regname = shift ;
   my $regval = shift ;

   return undef  unless defined($regmap{$regname}) ;

   my $reg = $regmap{$regname} ;

# print "$regname (aka $reg) = $regval\n" ;

   if( $reg =~ /^meta:/ ) {
      # meta register, recurse to write  all the sub-values
      my @subreg = split /:/, substr($reg,5) ;
      my @subregval = split /[.]/, $regval ;
      my $retval = 1 ;
      return undef  unless( $#subreg == $#subregval ) ;

      for my $i ( 0..$#subreg ) {
         $retval &= setreg( $subreg[$i], $subregval[$i] ) or warn "Error setting sub-register ${subreg[$i]} to ${subregval[$i]}" ;
      };
      return $retval ;
   };

   my $msg = "~2001E1EC200E".$reg ;
   if( $reg =~ /^01/ ) {
      # Unpack a 32-bit little-endian floating point value
      $msg .= toupper(unpack("H*",pack("f<",$regval+0.0))) ;
   } elsif( $reg =~ /^00/ ) {
      # 32-bit value (desired value in first byte)
      $msg .= toupper(unpack("H*",pack("V",$regval+0))) ;
   } else {
      warn "Unrecognized type in register: $reg" ;
      return undef ;
   }
   my $reply = "" ;
# print "Sending: $msg\n" ;
   syswrite( SCC, $msg.msgchk($msg)."\r" );
   sysreadt( SCC, $reply, -1, 10 );
   chomp $reply ;
# print "Got reply: $reply\n" ;

   ### Returns "~2001E1000000FDA7" on success
   # Verify reply and checksum
   if( $reply !~ /^~2001E1000000FDA7$/ ) {
      print "WARNING: Unexpected response\nReceived: $reply\nExpected: ~2001E1000000FDA7", msgchk(substr($reply,0,-4)), "\n" ;
      return undef ;
   }

   return 1 ;
};

### getall(): Read and display "all" parameters in a pretty format
sub getall () {
   # Dump static configuration
   printf "DHCP: %02d (00=disabled, 01=enabled)\n", getreg("dhcp");
   printf "LINK: %02d\n", getreg("link");
   print  "  IP: ", getreg("ip"), " (only when DHCP=00)\n";
   print  "  GW: ", getreg("gw"), "\n";
   print  "  SM: ", getreg("sm"), "\n";
   print  "TRAP: ", getreg("tp"), "\n";
   print  "Rect: ", getreg("numRect"), "\n";
   print  "  N+: ", getreg("numRedRect"), "\n";
   print  " BBU: ", getreg("numBBU"), "\n";
   print  "Vout: ", getreg("outmV"), " mVolts (currently)\n" ;
   printf "Vout: %.3f Volts (at reset)\n", getreg("outVnv") ;

   return ;
};

# print "#ARGV = $#ARGV\n" ;
if( $#ARGV < 0 ) {
   # No arguments, push an implied "all"
   push @ARGV, "all" ;
};

# Go through list and process them.
for my $arg ( @ARGV ) {
# print "Processing arg: $arg\n" ;
   if( $arg =~ m/=/ ) {
      my ($k, $v) = split "=", $arg ;
      print "Set $k to $v -- " ;
      if( setreg( $k, $v ) ) {
         print "SUCCESS.\n" ;
      } else {
         print "FAILED.\n" ;
      };
   } elsif( $arg eq "all" ) {
      getall( );
   } else {
      printf "%-4s: %s\n", $labels{$arg}, getreg( $arg );
   };
};

print "\n" ;

# Restore the terminal settings
$saved_tio->setattr( fileno(SCC), &POSIX::TCSANOW );

close( SCC ) or warn( "Problem closing port: $!" );
