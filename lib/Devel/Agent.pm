package Devel::Agent;

=head1 NAME

Devel::Agent

=head1 SYNOPSIS

  perl -d:Agent

=head1 DESCRIPTION

For years people in the perl commnity have been asking for a way to do performance monitoring and tracing of runtime production code. This module attempts to fill this role by implementing a stripped down debugger that is intended to provides an agent or agent like interface for perl 5.34.0+ that is simlilar in nature to the agent interface in other langagues Such as python or java.  

This is accomplished by running the script or code in debug mode, "perl -d:Agent"  and then turning the debugger on only as needed to record traching and performance metrics.  That said this module just provides an agent interface, it does not act on code directly until something turns it on.

=cut

use strict;
use warnings;
use 5.34.0;
our $VERSION=.0001;

our %VER_FIX;
BEGIN {

  # the only option 
  # for details see perldoc perlvar 
  # and check the $PERLDB section
  my @DEFAULT=(

    # -- this has to be enabled
    # Do not debug
    #0x01,

    # -- this has to be enabled
    # Disable DB::DB 
    #0x02,

    # keep optimizations on
    0x04,

    # do not save extra data
    0x08,

    # don't save line settings
    0x10,

    # -- this has to be enabled
    # disable single step
    #0x20,

    # do not use suroutine address
    0x40,

    # disable goto reporting
    0x80,

    # do not proivde informative file
    0x100,

    # don't bother with informative names
    0x200,

    # do not save source in @{"_<$filename"}
    0x400,

    # do not save evals that generate no subs
    0x800,

    # do not save uncompiled source code
    0x1000,

  );


  $VER_FIX{default}=\@DEFAULT;
  $VER_FIX{'v5.34.0'}=\@DEFAULT;
  my @DB_DISABLE;
  if(exists $VER_FIX{$^V}) {
    @DB_DISABLE=$VER_FIX{$^V}->@*;
  } else {
    @DB_DISABLE=$VER_FIX{default}->@*;
  }

  foreach my $opt (@DB_DISABLE) {
    $^P=$^P & ($^P ^ $opt);
  }

  # may or may not be compiled with -Dxx option
  eval { $^D =0};
}


=head1 Agent interface

The Agent interface is implemented via an on demand debugger that can be turned on/off on the fly.  Also it is possible to run multiple different debugger instances with diffrent configurations on different blocks of code.   This was done intentionally as perl is fairly complex in its nature and an agent interface isn't very useful unless it is flexible.

The agent interface itself is activated by setting $DB::Agent to an instance of itself.

=head1 DB Constructor options

This section documents the %args the be passed to the new DB(%args) or DB->new(%args) call.  For each option documented in this section, there is an accesor by that given name that can be called by $self->$name($new_value) or my $current_value=$self->$name.

=cut

# prevent indexing ( as ya this will be noticed in the indexing process for sure!!! )
package 
  DB;

# ADD THIS TO THE SYNOPSIS!!!
# PERL5OPT='-d:Agent'

#use Modern::Perl;
use strict;
use warnings;

# as easy as Moo makes things.. its not welcome in a debugger ;(
use Time::HiRes qw(gettimeofday tv_interval);
use B qw(svref_2object);
#use Data::Dumper;

our $AGENT;
my $IN_METHOD=0;
my $internals=0;

# ya no, only allow access to this class!!
my %BUILD_ARGS;

# Genrate functions similar to moo and moose, but don't actually use Moo or Moose..
sub has {
  my ($method,%args)=@_;

  my $ref=ref $args{default};
  $BUILD_ARGS{$method}=\%args;
  unless($ref) {
    my $default=$args{default};
    $args{default}=sub { $default };
  }
  if($args{clearer}) {
    my $sub=sub {
       my $self=shift;
      delete $self->{$method};
    };
    my $method="clear_$method";
    my $method_name=__PACKAGE__."::$method";
    no strict 'refs';
    *{$method_name}=$sub;
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
  no strict 'refs';
  my $method_name=__PACKAGE__."::$method";
  *{$method_name}=$sub;
}

sub new {
  my ($class,%args)=@_;
  my $self=bless {},$class;
  while(my ($key,$args)=each %BUILD_ARGS) {
    if(exists $args{$key}) {
      $self->{$key}=$args{$key};
    } elsif(!$args->{lazy}) {
      my $cb=$args->{default};
      $self->{$key}=$self->$cb();
    }
  }
  return $self;
}

#use constant DEFAULT_DEPTH=>4;
# use prototype to declare constant
sub DEFAULT_DEPTH () { 4 }

our @EXCLUDE_DEFAULTS=(
  __PACKAGE__,
  qw(
    DB
    Data::Dumper
    Time::HiRes
    Method::Generate::Accessor
    MooX::Types::MooseLike
    Method::Generate::Accessor::_Generated
    Moo::HandleMoose::AuthorityHack
    Method::Generate::Constructor
    Sub::Quote
    strict
    warnings
    Sub::Defer
  )
);

=over 4

=item * level=>ArrayRef

This is an auto generated array ref that is use by the internals to track current stack level state information.

=cut

has level=>(
  is=>'rw',
  #isa=>ArrayRef,
  lazy=>1,
  default=>sub { [] },
  clearer=>1,
);

=item * resolve_constructor=>Bool

This option is used to turn on or off the resolution of a class name when being constructed and other situations.  By default this option is set to true.

=cut

has resolve_constructor=>(
# isa=>Bool,
  is=>'ro',
  default=>1,
);

=item * trace=>[]

When the object instance is constructed with save_to_stack=>1 ( default is: 0 ) then the stack trace will be saved into a single multi tier data structrure represented by $self->trace.

=cut

has trace=>(
# isa=>ArrayRef,
  is=>'rw',
  default=>sub {
    return [];
  },
  lazy=>1,
  clearer=>1,
);

=item * ignore_calling_class_re=>ArrayRef[RegexpRef]

This option allows a list of calling calsses to be ignored when they match the regular expression.

Example ignore_calling_class_re being set to [qr{^Do::Not::Track::Me::}] will prevent the debugger for trying to trace or record calls made by any methods within "Do::Not::Track::Me::".  This does not prevent this class from showing up fully ina stack trace.  If this class calls a class that calls another class that calls a class unlisted in ignore_calling_class_re, then Do::Not::Track::Me::xxx will show up as the owner frame of the calls as a biproduct of correctness in stack tracing.

=cut

has ignore_calling_class_re=>(
# isa=>ArrayRef[RegexpRef],
  is=>'ro',
  default=>sub {
    return [];
  },
);

=item * excludes=>HashRef[Int]

This is a collection of classes that should be ignored when they make calls. The defaults are defined in @DB::EXCLUDE_DEFAULTS and include classes like Data::Dumper and Time::HiRes to name a few.  For a full list of the current defaults just perl -MDevel::Agent -MData::Dumper -e 'print Dumper(\@DB::EXCLUDE_DEFAULTS)'

=cut

has excludes=>(
# isa=>HashRef[Int],
  is=>'ro',
  default=>sub {
    return { 
      map {($_,1)}  
      @EXCLUDE_DEFAULTS
    }
  },
);

=item * last_error=>Str

This is used by the trace process to determine where the last $@ was defined, this value is reset on each trace.

=cut

has last_error=>(
  is=>'rw',
  lazy=>1,
  clearer=>1,
  default=>sub {
    my $str='';
    return $str;
  },
);

=item * last_depth=>Int

This value is used at runtime to determine the previous point in the stack trace.

=cut

has last_depth=>(
  default=>0,
  lazy=>1,
  is=>'rw',
  clearer=>1,
# isa=>Int,
);

=item * depths=>ArrayRef

This is used at runtime to determin the current frame stack depth.  Each currently executing frame is kept in order from top to the bottom of the stack.

=cut

has depths=>(
  is=>'rw',
  lazy=>1,
# isa=>ArrayRef,
  clearer=>1,
  default=>sub { return [] },
);

=item * order_id=>Int

This option acts as the sequence or order of execution counter for frames.  When a frame starts $self->order_id is incremented by 1 and set to the frame's oder_id when the frame has completed execution the current $self->order_id is incremented again and set to the frame's end_id.

=cut

has order_id=>(
# isa=>Int,
  is=>'rw',
  lazy=>1,
  default=>0,
  clearer=>1,
);

=item * save_to_stack=>Bool

This option is used to turn on or of the saving of frames details in to a layered structure inside of $self->trace.  The default is 0 or false.

=cut

has save_to_stack=>(
# isa=>Bool,
  is=>'rw',
  default=>0,
);

=item * on_frame_end=>CodeRef

This code ref is called when a frame is closed.  This should act as the default data streaming hook callback.  All tracing operations are halted durriong this callback.

Example:

  sub {
    my ($self,$last)=@_;

    # $self: An instance of DB
    # $last: The most currently closed frame
  }

=cut

has on_frame_end=>(
# isa=>CodeRef,
  is=>'rw',
  default=>sub { sub {} },
);

=item * trace_id=>Int

This method provides the current agent tracing pass.  This number is incremented at the start of each call to $self->start_trace.

=cut

has trace_id=>(
  is=>'rw',
  default=>0,
  lazy=>1,
);

=item * ignore_blocks=>HasRef[Int]

This hashref reprents what perl phazed blocks to ignore, the defaults are.

  {
    BEGIN=>1, 
    END=>1,  
    INIT=>1,
    CHECK=>1,
    UNITCHECK=>1,
  }

The default values used to generate the hashref contained in in @DB::@PHAZES

=cut

our @PHAZES=(qw(BEGIN  END  INIT  CHECK  UNITCHECK));
has ignore_blocks=>(
  #isa=>HashRef[Int],
  is=>'ro',
  default=>sub {
    return { map { ($_,1) } @PHAZES}
  },
);

has constructor_methods=>(
  is=>'ro',
  #isa=>HashRef,
  default=>sub {
    return { 
     new=>1,
    };
  }
);
has max_depth=>(
  is=>'rw',
  lazy=>1,
  clearer=>1,
  default=>-1,
);

has tid=>(
  is=>'rw',
  clearer=>1,
  lazy=>1,
  default=>sub {
    my $tid=1;
    eval { $tid=threads->tid };
    return $tid;
  },
);

has existing_trace=>(
  is=>'rw',
  #isa=>Maybe[InstanceOf['DB']],
  lazy=>1,
  default=>sub { undef },
);

=item * process_result=>CodeRef

This callback can be used to evaluate/modify the results of a callback. 

Example callback

  sub {
    my ($self,$type,$frame)=@_;
    # $self:  Instance of Devel::Agent
    # $type:  -1,0,1
    # $frame: The current frame
  }

Notes on $type and where the current return values are stored

When $type is:
  -1 This is in a call to DESTROY( the envy of the programming world! )
    Return value is in $DB::ret

  0  This method was called in a scalar context
    Return value is in $DB::ret

  1  This method was called in a list context
    Return value is in @DB::ret

=cut

has process_result=>(
  is=>'ro',
  #isa=>CodeRef,
  default=>sub { sub {} },
  lazy=>1,
);

=item * filter_on_args=>CodeRef

This allows a code ref to be passed in to filter arguments passed into an method.  If the method returns false, the frame is ignored.

Default always returns true

  sub  { 
    my ($self,$frame,$args,$caller)=@_;
    # $self:   Instance of Devel::Agent
    # $frame:  Current frame hashref
    # $args:   The @_ contents
    # $caller: The contents of caller($depth)
    return 1; 
  }

=cut

has filter_on_args=>(
  is=>'ro',
  #isa=>CodeRef,
  default=>sub { sub {1} },
  lazy=>1,
);


has pid=>(
  is=>'ro',
  default=>$$,
  #isa=>Int,
);

sub _filter {
  my ($self,$caller,$args)=@_;
  
  return 0 unless defined($caller->[0]);
  foreach my $re (@{$self->ignore_calling_class_re}) {
    if($caller->[0]=~ $re) {
      return 0;
    }
  }
  return 0 if exists $self->excludes->{$caller->[0]};
  my $caller_class=$caller->[3];
  return 0 unless defined $caller_class;

  my ($class,$method)=$caller_class=~ m/^(.*)::(.*)$/;

  $self->resolve_class($class,$method,$caller,$args);

  return 0 if exists $self->excludes->{$class};
  return 1;
}

sub resolve_class {
  my ($self,$class,$method,$caller,$args)=@_;
  return unless $#{$args}!=-1 && defined($args->[0]);

  if($self->resolve_constructor && exists $self->constructor_methods->{$method} ) {
    my $new_class=$args->[0];
    if($new_class->DOES($class)) {
      $caller->[3]=$class.'::'.$method;
      $_[1]=$new_class;
    }
  }
}

sub close_depth {
  my ($self,$depth)=@_;

  # work around for the $self->stop_trace;
  return unless defined $self->depths->[$depth];

  my $last=pop $self->depths->@*;
  if($@ && $self->last_error ne $@) { 
    $last->{error}=1;
    $self->last_error($@);
  } else {
    $last->{error}=0;
  }
  my $t0=delete $last->{t0};
  my $d=tv_interval($t0);
  #$d=0 if index($d,'e')!=-1; # how is this slower than a regex? wow!!!
  $d=0 if $d=~ /e/s;
  $last->{duration}=$d;
  $last->{end_id}=$self->next_order_id,
  my $tmp=$internals;
  $internals=1;
  $self->on_frame_end->($self,$last);
  $internals=$tmp;
}

sub next_order_id {
  my ($self)=@_;
  return $self->order_id(1+$self->order_id);
}

sub close_to {
  my ($self,$to,$last)=@_;

  if($to<=$self->max_depth) {
    # reset our max depth to -1;
    $self->max_depth(-1);
  }

  my $target;
  my $size=$self->depths->$#*;
  for(my $depth=$size;$depth>0;--$depth) {
    if($depth==$to) {
      $self->close_depth($depth);
      $target=$to;
      last; 
    } elsif($depth < $to) {
      $target=$depth;
      last;
    } else {
      $self->close_depth($depth);
    }
  }
  if(defined($target)) {
    $self->save_to($last) if defined($last);
  } elsif(defined($last)) {
    $self->save_to($last);
  }
  $self->last_depth($to);
}

sub filter{
  my ($self,$caller,$args)=@_;

  $self->pause_trace;
  my $raw_caller=[@$args];
  return $self->restore_trace unless $self->_filter($caller,$args);
  my $last=$self->caller_to_ref($caller,undef,$DB::sub,0);
  return $self->restore_trace unless defined($last);

  unless($self->filter_on_args->($self,$last,$args,$raw_caller)){
    $self->restore_trace;
    return;
  }

  $self->push_to_stack($last);
  my $level=$self->level;
  push $level->[$level->$#*]->@*,$self->last_depth;
  $self->restore_trace;
}

sub save_to {
  my ($self,$last)=@_;
  
  my $depth=$last->{depth};
  $self->depths->[$depth]=$last;

  $self->last_depth($depth);
  # stop here unless someone wants the frames saved in memory
  return unless $self->save_to_stack;
  if($depth==1) {
    push $self->trace->@*,$self->depths->[$depth]=$last;
  } else {
    my $root=$depth -1;
    push $self->depths->[$root]->{calls}->@*,$self->depths->[$depth]=$last;
  }
}

sub push_to_stack {
  my ($self,$last)=@_;

  my $depth=$last->{depth};
  my $last_depth=$self->last_depth;
  if($last_depth==0) {
    $self->save_to($last);
  } elsif($depth<= $last_depth) {
    $self->close_to($depth,$last);
  } else {
    $self->save_to($last);
  }
}

sub get_depth {
  my ($self)=@_;
  my $start = DEFAULT_DEPTH;
  # skip un-needed depth checking
  $start +=$self->depths->$#* if $self->depths->$#* >0;
  my $depth=$start - DEFAULT_DEPTH;

  my $caller=[caller($start)];
  my $no_frame=[];
  my $max=$self->max_depth;
  while($caller->$#*!=-1) {
    if($max!=-1) {
      my $pos=$depth +1;
      if($pos>$max) {
        return undef;
      }
    }

    if($start !=DEFAULT_DEPTH) {
      unless(defined $self->depths->[$depth]) {
        push $caller->@*,$depth;
        push $no_frame->@*,$caller;
      }
    }
    ++$start;
    $caller=[caller($start)];
    $depth=$start - DEFAULT_DEPTH;
  }
  foreach my $caller ($no_frame->@*) {
    my $depth=pop $caller->@*;
    my $last=$self->caller_to_ref($caller,$depth,$caller->[3],1);
    $self->push_to_stack($last);
  }
  return $start - DEFAULT_DEPTH;
}

sub caller_to_ref {
  my ($self,$caller,$depth,$raw_method,$no_frame)=@_;
  $no_frame=0 unless defined($no_frame);
  my ($p,$f,$l,$s,$h,$w,$e,$r)=@$caller;
  if(defined($e)) {
    $e='...';
  }
  if ($r) {
    $s = "require '$e'";
  } elsif (defined $r) {
    $s = "eval '$e'";
  } elsif ($s eq '(eval)') {
     $s = "eval {...}";
  }
  $f = "file '$f'" unless $f eq '-e';

  $depth=$self->get_depth unless defined($depth);
  unless(defined($depth)) {
    return undef;
  }

  my $root=$depth -1;
  my $owner_id=0;
  if($root!=0 && defined $self->depths->[$root]) {
    $owner_id=$self->depths->[$root]->{order_id};
  }
  
  my $ref={ 
    raw_method=>(ref($raw_method) ? 'sub { ... }' : $raw_method ),
    owner_id=>$owner_id,
    depth=>$depth,
    order_id=>$self->next_order_id,
    calls=>[],
    t0=>[gettimeofday],
    #t0=>[time,0],
    class_method=>$s,
    source=>$f,
    line=>$l,
    caller_class=>$p,
    no_frame=>$no_frame,
    meta=>{},
    end_id=>0,
  };

  return $ref;
}

sub reset {
  my ($self)=@_;
  $self->clear_trace;
  $self->clear_last_error;
  $self->clear_last_depth;
  $self->clear_depths;
  $self->clear_order_id;
  $self->clear_level;
  $self->clear_tid;
  $self->clear_max_depth;
}

sub start_trace {
  my ($self)=@_;
  $self->reset;
  $self->trace_id($self->trace_id +1);
  $AGENT=$self;
}

sub stop_trace {
  my ($self)=@_;
  $self->close_to(0);
  $AGENT=undef;
}

sub DB {
  return unless $IN_METHOD;
  $IN_METHOD=0;

  $AGENT->filter([caller 1],\@_);
}

sub pause_trace {
  my ($self)=@_;
  $AGENT=undef;
  $IN_METHOD=0;
}

sub restore_trace {
  my ($self)=@_;
  $AGENT=$self;
}

sub close_sub {
  my ($self,$res)=@_;
  $self->pause_trace;
  my $level=pop $self->level->@*;

  if($level->$#*==0) {
    $self->restore_trace;
    return;
  }
  my $depth=$level->[1];
  my $last=$self->depths->[$depth];
  $self->process_result->($self,$res,$last);
  $self->close_to($depth);
  $self->restore_trace;
}

sub sub {
  if($IN_METHOD 
    || !defined($AGENT) 
    || $internals 
    || substr($DB::sub,0,4) eq 'DB::' 
    || ${^GLOBAL_PHASE} ne 'RUN'
  ) {
    no strict 'refs';
    return &$DB::sub 
  }
  
  
  if(ref($DB::sub)) {
    my $name=svref_2object($DB::sub)->GV->NAME;
    if(defined($name) && exists $AGENT->ignore_blocks->{$name}) {
      my $agent=$AGENT;
      $IN_METHOD=0;
      $AGENT=undef;
      if(wantarray) {
        @DB::ret = &$DB::sub;
        $AGENT=$agent;
        my @list=@DB::ret;
        @DB::ret=();
        return @list;
      } else {
        $DB::ret = &$DB::sub;
        $AGENT=$agent;
        return $DB::ret;
      }
    }
  }
  push $AGENT->level->@*,[$DB::sub];

  $IN_METHOD=1;
  
  no strict 'refs';
  if ($DB::sub eq 'DESTROY' or substr($DB::sub, -9) eq '::DESTROY' or not defined wantarray) {
    $DB::ret=&$DB::sub;
    $AGENT->close_sub(-1);
    $DB::ret = undef;
  } elsif (wantarray) {
    @DB::ret = &$DB::sub;
    $AGENT->close_sub(1);
    @DB::ret;
  } else {
    $DB::ret = &$DB::sub;
    $AGENT->close_sub(0);
    $DB::ret;
  }
}

sub DESTROY {
  my ($self)=@_;
}

1;

__END__

=head1 Compile time notes

For perl 5.34.0

When loading this moduel All features of the debugger are disabled aside from: ( 0x01, 0x02, and 0x20 ) which are requried to force the execution of DB::DB. Please see the perldoc perlvar and the $PERLDB section.

  Which means:    $^P==35
  Also as a note: $^D==0

=head1 RUNTIME

At runtime, this modue tries to exectue $Devel::Agent::AGENT->filter($caller,$args).  If $Devel::Agent::AGENT is not defined, then nothing happens.

  $caller: is the caller information
  $args:   contains an array reference that represents the arguments passed to a given method

=head1 AUTHOR

Michael Shipper L<AKALINUX@CPAN.ORG>

=cut

