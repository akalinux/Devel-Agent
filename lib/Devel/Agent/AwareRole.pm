package Devel::Agent::AwareRole;

use Modern::Perl;
use Role::Tiny;
require Scalar::Util;


sub ___db_stack_filter { 
  my ($class,$agent,$frame,$args,$raw_caller)=@_; 

  $agent->max_depth($frame->{depth}); 

  if(my $blessed=&Scalar::Util::blessed($class)) {
    $class=$blessed;
  }
  

  return 0 if $frame->{caller_class} eq $class;

  my $replace=$class.'::';
  $frame->{class_method}=~ s/^(.*)::/$replace/s;
  $frame->{raw_method}=~ s/^(.*)::/$replace/s;
  return 1;
} 


1;
