package Devel::Agent::Proxy;

# would love to use Moo, but artifacts are bad!
use strict;
use warnings;
require Carp;

# COMMENT THIS OUT AFTER TESTING!!
#use Data::Dumper;

our $AUTOLOAD;

our %BUILD_ARGS;

my $has=sub {
  my ($method,%args)=@_;

  my $ref=ref $args{default};
  $BUILD_ARGS{$method}=\%args;
  unless($ref) {
    my $default=$args{default};
    $args{default}=sub { $default };
  }
  my $sub=sub {
    my $self=shift;
    if($#_==-1) {
      if(exists $self->{$method}) {
        return $self->{$method};
      } else {
        my $def=$args{default};
        my $value=$self->{$method}=$self->$def();
        return $value;
      }
    } else {
      return $self->{$method}=$_[0];
    }
  };
  my $method_name=__PACKAGE__."::___$method";
  no strict 'refs';
  *{$method_name}=$sub;
};

$has->(wrap_result_methods=>(
  #isa=>HashRef[CodeRef],
  is=>'ro',
  lazy=>1,
  default=>sub {
    return {};
  },
));

$has->(proxy_class_name=>(
  #isa=>Str,
  is=>'ro',
  required=>1,
));

$has->(replace_name=>(
  #isa=>Str,
  is=>'rw',
  lazy=>1,
  default=>sub {
    my ($self)=@_;
    return $self->___proxy_class_name.'::';
  },
));

$has->(proxied_object=>(
  #isa=>Object,
  required=>1,
  is=>'ro',
));

$has->(debugger_agent=>(
  is=>'ro',
  required=>1,
  #isa=>InstanceOf['DB'],
));

$has->(current_method=>(
  is=>'rw',
  required=>1,
));

$has->(in_can=>(
  is=>'rw',
  default=>0,
  lazy=>1,
));
undef $has;
sub new {
  my ($class,%args)=@_;
  my $self=bless {},$class;
  while(my ($key,$args)=each %BUILD_ARGS) {

    if(exists $args{$key}) {
      $self->{$key}=$args{$key};
    } elsif($args->{required}) {
      &Carp::croak("$key is a required argument");
    } elsif(!$args->{lazy}) {
      my $cb=$args->{default};
      $self->{$key}=$self->$cb();
    }
  }
  return $self;
}

sub ___db_stack_filter {
  my ($self,$agent,$frame,$args,$raw_caller)=@_;
  return 1 unless ref $self;

  # hide all the calls we make
  return 0 if $frame->{caller_class} eq __PACKAGE__;
  my $replace=$self->___replace_name;
  $frame->{class_method}=~ s/^(.*)::/$replace/s;
  $frame->{raw_method}=~ s/^(.*)::/$replace/s;
  return 1;
}

sub can {
  my ($self,$method)=@_;
  my $p=$self->___proxied_object;

  my $cb=$p->can($method);
  return $cb unless $cb;
  $self->___current_method($method);

  return sub {
    $self->___in_can(1);
    $AUTOLOAD=$method;
    $self->$method(@_);
  };
}

sub isa {
  my ($self,$class)=@_;
  return $self->___proxied_object->isa($class);
}

sub DOES {
  my ($self,$role)=@_;
  return $self->___proxied_object->DOES($role);
}

sub AUTOLOAD {
  # do this so we can pass @_ to our target function
  my $self=shift;
  my $method=$AUTOLOAD;
  $method=~ s/^.*:://s;
  $self->___current_method($method);
  my $p=$self->___proxied_object;

  my $cb;
  if($self->___in_can) {
    return $self->___exec_method($self->__in_can,@_);
  } if($cb=$p->can($method)) {
    $self->___current_method($method);
    return $self->___exec_method($cb,@_);
  } elsif($cb=$p->can('AUTOLOAD')) {
    $self->___current_method('AUTOLOAD');
    return $self->___exec_method($cb,@_);
  }
    
  Carp::croak(sprintf q{Can't locate object method "%s" via package "%s"},$method,$self->___proxy_class_name);
}

sub ___exec_method {
  my $self=shift;
  my $cb=shift;
  my $wrap=$self->___wrap_result_methods;
  my $method=$self->___current_method;
  $self->___in_can(0);
  my $p=$self->___proxied_object;
  local $@;
  if(wantarray) {
    my @res;
    @res=$p->$cb(@_);
    if(exists $wrap->{$method}) {
      $wrap->{$method}->($self,1,\@res);
    }
    return @res;
  } else {
    my $res;
    $res=$p->$cb(@_);
    if(exists $wrap->{$method}) {
      $wrap->{$method}->($self,0,$res);
    }
    return $res;
  }
}

# manditory in the case of auto load!!
sub DESTROY {
  my ($self)=@_;
  undef $self;
}

1;
