use Modern::Perl;
use FindBin qw($Bin);

use lib $Bin;

use TestA;
use TestB;


print "trace on\n";
$Devel::Agent::TRACE=1;
my $self=new TestA;

$self->test_a;
my $obj=new TestB(asdvas=>1);
$obj->test_a;

foreach (qw(a b c )) {
  print "test: $_\n";
}
test_a();
$obj->test_a;
$Devel::Agent::TRACE=0;
print "trace off\n";

$self->test_a;
$obj->test_a;

sub test_a {
  print "testing\n";
}
