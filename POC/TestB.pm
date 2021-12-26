package TestB;

use Modern::Perl;
use Moo;

extends 'TestA';

sub test_a {
  my ($self,@args)=@_;
  $self->SUPER::test_a(@args);
}
1;
