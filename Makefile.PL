use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME         => 'CGI::Persist',
    VERSION_FROM => 'lib/CGI/Persist.pm', # finds $VERSION
    AUTHOR       => 'Hartog C. de Mik <hartog@2organize.com>',
    ABSTRACT     => 'Stateless CGI scripts with perl',
    PREREQ_PM    => { 'Storable'             => 1,
		      'Class::AccessorMaker' => 1,
                    },
);
