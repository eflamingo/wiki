use 5.014002;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Foswiki',
    VERSION_FROM      => 'lib/Foswiki.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ABSTRACT_FROM     => 'lib/Foswiki.pm', # retrieve abstract from module
    AUTHOR            => 'Joel DeJesus (Work Email) <dejesus.joel@e-flamingo.jp>',
    ,'EXE_FILES' => [
         'script/foswiki_accounts'
        ,'script/foswiki_attach'
        ,'script/foswiki_changes'
        ,'script/foswiki_configure'
        ,'script/foswiki_edit'
        ,'script/foswiki_login'
        ,'script/foswiki_logon'
        ,'script/foswiki_manage'
        ,'script/foswiki_oops'
        ,'script/foswiki_preview'
        ,'script/foswiki_previewauth'
        ,'script/foswiki_rdiff'
        ,'script/foswiki_rdiffauth'
        ,'script/foswiki_register'
        ,'script/foswiki_rename'
        ,'script/foswiki_resetpasswd'
        ,'script/foswiki_rest'
        ,'script/foswiki_restauth'
        ,'script/foswiki_save'
        ,'script/foswiki_search'
        ,'script/foswiki_sip'
        ,'script/foswiki_sipregister'
        ,'script/foswiki_statistics'
        ,'script/foswiki_upload'
        ,'script/foswiki_view'
        ,'script/foswiki_viewauth'
        ,'script/foswiki_viewfile'
        ,'script/foswiki_viewfileauth'
    ]
    #LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #http://search.cpan.org/perldoc?Module%3A%3ABuild%3A%3AAPI
);
