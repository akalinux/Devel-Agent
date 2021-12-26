#!/opt/apps/perl/perl5240/bin/perl

use Modern::Perl;
use Data::Dumper;

sub has {
  print Dumper(\@_);
}
has 1,2,3;
