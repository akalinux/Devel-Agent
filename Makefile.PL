use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Charter',
    EXE_FILES=>[
     qw(
      bin/SolarWindsSQL.pl  
      bin/uta_snmp_trap.pl
      bin/tw_uta.pl
      bin/cpm_get_node_byip.pl 
      bin/cpm_bulk_ip.pl
      bin/ldap_tool.pl
      bin/cpm_get_uri.pl
      )
    ],
    VERSION  => '1.02', # finds $VERSION
    PREREQ_PM         => {
    qw(
     IO::Socket::SSL 1.968
     LWP::UserAgent  6.04
     MIME::Base64    3.13
     URI::Encode     0.09
     JSON            2.53
     IO::Scalar      2.11
     Net::SSLeay     1.58
    )
    }
);

