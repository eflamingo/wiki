# See bottom of file for license and copyright information

=pod TML

---+ package Foswiki::UI::Accounting

Handling peeps.

=cut

package Foswiki::UI::Accounting;

use strict;
use warnings;
use Assert;
use Error qw( :try );
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Data::Dump qw(dump); # I prefer this to Data::Dumper
use Foswiki                ();
use Foswiki::OopsException ();
use Foswiki::Sandbox       ();
use Foswiki::UI            ();
use Foswiki::Contrib::DBIStoreContrib::Handler();

BEGIN {

    # Do a dynamic 'use locale' for this module
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

my $pgsqlnamespace = "accounts";
my $handlerTables = { Splits => qq/accounts."Splits"/, Transactions => qq/accounts."Transactions"/};

sub getTable {
	my $table_name = shift;
	return $handlerTables->{$table_name} if $handlerTables->{$table_name};
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	return Foswiki::Contrib::DBIStoreContrib::Handler::returnHandlerTables($table_name);
}

my $productTypes = { Sites => {table=>'foswiki."Sites"'}, Credits => {table=>'accounting."Credit_History"'}};
sub getProductType {
	my $type = shift;
	return $productTypes->{$type}->{table};
}
# gets the table name from dbistorecontrib
sub getTableName {
	my $table = shift;
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	return Foswiki::Contrib::DBIStoreContrib::Handler::returnHandlerTables($table);
}
=pod TML

---++ StaticMethod register_user( $session )

=register_user= command handler.
This method is designed to be
invoked via the =UI::run= method.

Generate xml for Freeswitch to munch on.
If a user is not found, then 404 the request.
---++ Public Data members of the Session Object
   * =request=          Pointer to the Foswiki::Request
   * =response=         Pointer to the Foswiki::Response
   * =context=          Hash of context ids
   * =plugins=          Foswiki::Plugins singleton
   * =prefs=            Foswiki::Prefs singleton
   * =remoteUser=       Login ID when using ApacheLogin. Maintained for
                        compatibility only, do not use.
   * =requestedWebName= Name of web found in URL path or =web= URL parameter
   * =scriptUrlPath=    URL path to the current script. May be dynamically
                        extracted from the URL path if {GetScriptUrlFromCgi}.
                        Only required to support {GetScriptUrlFromCgi} and
                        not consistently used. Avoid.
   * =security=         Foswiki::Access singleton
   * =store=            Foswiki::Store singleton
   * =topicName=        Name of topic found in URL path or =topic= URL
                        parameter
   * =urlHost=          Host part of the URL (including the protocol)
                        determined during intialisation and defaulting to
                        {DefaultUrlHost}
   * =user=             Unique user ID of logged-in user
   * =users=            Foswiki::Users singleton
   * =webName=          Name of web found in URL path, or =web= URL parameter,
                        or {UsersWebName}
=cut

sub accounting {
	my $session = shift;
	# Need to make sure the site is on e-flamingo.net
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $site_name = $handler->getSiteName();

    my $action = $session->{request}->param('action');
	
    # Dispatch to action function
    if ( defined $action ) {
        my $method = 'Foswiki::UI::Accounting::_action_' . $action;
		
        if ( defined &$method ) {
        	
            no strict 'refs';
            &$method($session);
        }
        else {

            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => [$action]
            );
        }
    }
    else {
        throw Foswiki::OopsException( 'attention', def => 'missing_action' );
    }
}
# create transaction (and topic page)
sub _action_create_tx {
	my $session = shift;
	#my $uri = $session->{request}->uri();
	#die "URI:$uri";
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $site_name = $handler->getSiteName();
	#my $bool = Foswiki::Func::checkAccessPermission_cUID( 'VIEW', $session->{user}, '', $session->{topicName}, $session->{webName} );
	require Foswiki::Plugins::AccountingPlugin::Ledger;

	Foswiki::Plugins::AccountingPlugin::Ledger::create_tx($session);
    
}

# create accounting book (along with new web)
sub _action_Create_NewBook{
	my $session = shift;
}
1;
__END__

After the script is done, redirect here

        my $viewURL = $session->getScriptUrl( 1, 'view', $w, $t );
        $session->redirect( $session->redirectto($viewURL), undef, 1 );


