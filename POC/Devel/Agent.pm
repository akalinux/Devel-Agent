package Devel::Agent;

use strict;
our $TRACE=0;
1;
package DB;
use strict;
use Data::Dumper;

our $METHOD;
our $IN_METHOD=0;
sub DB { 
  
  return unless $TRACE;
  return unless $IN_METHOD;
  $TRACE=0;
  $IN_METHOD=0;

  my $args=[@_];
  my $caller=[caller];
  print Dumper($caller,$args);
  print "in db: $METHOD sub: $DB::sub\n";
  $TRACE=1;
}

sub sub {
  no strict 'refs';
  return &$DB::sub unless $TRACE;

  $IN_METHOD=1;
  $METHOD=$DB::sub;
  if(wantarray) {
    my $res=[&$DB::sub];

    return $res->@*;
  } else {
    my $res=&$DB::sub;
    return $res;
  }
  
}

1;
