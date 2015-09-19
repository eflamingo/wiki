# See bottom of file for license and copyright information

=pod TML

---+ package Foswiki::UI::Accounts

Handling peeps.

=cut

package Foswiki::UI::Accounts;

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

my $productTypes = { Sites => {table=>'foswiki."Sites"'}, Credits => {table=>'accounts."Credit_History"'}};
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

sub accounts {
	my $session = shift;
	# Need to make sure the site is on e-flamingo.net

	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $action = $session->{request}->param('action');
	my $site_name = $handler->getSiteName();
	my $ok_actions = {'change_user_config' => 1, 'activate_site' => 1, 'order_deposit' => 1, 'order_withdrawal' => 1,
		 'order_both' => 1, 'fill_deposit' => 1, 'fill_withdrawal' => 1, 'fill_both' => 1};
	# order_deposit and order_withdrawal and order_both should work for any site (anyone can use these)
	
	if($site_name ne 'e-flamingo.net' && $site_name ne 'tokyo.e-flamingo.net' && $site_name ne 'practice-tokyo.e-flamingo.net' && !$ok_actions->{$action} ){
		throw Foswiki::OopsException( 'attention', def => 'wrong_site' );
	}
	
	
	
	# Dispatch to action function
	if ( defined $action ) {
		my $method = 'Foswiki::UI::Accounts::_action_' . $action;

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
	# redirect to the new page
	#my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $session->{webName}, $session->{topicName} ) );
	#$session->redirect($redirecturl);
}
####################################################################################################################
=pod
---+ deposits (anything related to paying cash and the user's account is credited)
   1. order - admin waits for bank transfer/cash payment to clear
   2. cancel - cancel deposit, no money is refunded, nor is the user's account debited
   3. fill - confirms that the admin has received cash payment and credits user's account
=cut

# done by user
sub _action_order_deposit {
    my $session = shift;
    require Foswiki::Plugins::AccountsPlugin::Orders;
    Foswiki::Plugins::AccountsPlugin::Orders::order_deposit($session);
}

# done by admin
sub _action_cancel_deposit {
    my $session = shift;
	# equate this to changing the topic
    my $bool = Foswiki::Func::checkAccessPermission_cUID( 'CHANGE', $session->{user}, '', $session->{topicName}, $session->{webName} );
    require Foswiki::Plugins::AccountsPlugin::Orders;
    Foswiki::Plugins::AccountsPlugin::Orders::cancel_deposit($session) if $bool;   
}

# done by admin
sub _action_fill_deposit {
    my $session = shift;
	# equate this to changing the topic
    my $bool = Foswiki::Func::checkAccessPermission_cUID( 'CHANGE', $session->{user}, '', $session->{topicName}, $session->{webName} );
    require Foswiki::Plugins::AccountsPlugin::Orders;
    Foswiki::Plugins::AccountsPlugin::Orders::fill_deposit($session) if $bool;   
}

# order_credit is being phased out..........
sub _action_order_credit {
	# order_deposit is the new thing
	_action_order_deposit(@_);
}
# being phased out ..........
sub _action_deliver_credit {
	_action_fill_deposit(@_);
}

####################################################################################################################
=pod
---+ Withdrawal (provisioning or consuming services in which user account is debited)
   1. order - deduct credits from account, wait for order to be filled by the admin
   2. cancel - readds credits previously deducted back to the account
   3. fill - confirms that the admin has delivered the product
   4. consume - creates and updates consumption invoices
=cut

# done by user
sub _action_order_withdrawal {
    my $session = shift;
    require Foswiki::Plugins::AccountsPlugin::Orders;
    Foswiki::Plugins::AccountsPlugin::Orders::order_withdrawal($session);
}
# done by admin
sub _action_fill_withdrawal {
    my $session = shift;
    require Foswiki::Plugins::AccountsPlugin::Orders;
    my $bool = Foswiki::Func::checkAccessPermission_cUID( 'CHANGE', $session->{user}, '', $session->{topicName}, $session->{webName} );
    Foswiki::Plugins::AccountsPlugin::Orders::fill_withdrawal($session) if $bool;
}
# done by admin
sub _action_cancel_withdrawal {
    my $session = shift;
    require Foswiki::Plugins::AccountsPlugin::Orders;
    my $bool = Foswiki::Func::checkAccessPermission_cUID( 'CHANGE', $session->{user}, '', $session->{topicName}, $session->{webName} );
    Foswiki::Plugins::AccountsPlugin::Orders::cancel_withdrawal($session) if $bool;
}
# done by admin
sub _action_consume_withdrawal {
    my $session = shift;
    require Foswiki::Plugins::AccountsPlugin::Orders;
    my $bool = Foswiki::Func::checkAccessPermission_cUID( 'CHANGE', $session->{user}, '', 'Main', 'WebHome' );
    Foswiki::Plugins::AccountsPlugin::Orders::consume_withdrawal($session) if $bool;
}
####################################################################################################################
=pod
---+ Sites 
   1. order_site - being phased out
   2. refresh_sites - used to update the dataform database in tokyo.e-flamingo.net with info from Sites sql table
   3. create_site - creates a new site, but does not activate it (topic_history derivatives such as Links, MetaPreferences are not written)
   4. activate_site - writes/does inserts for topic_history derivatives such as Links, MetaPreferences
   5. copy_site - copies a site to the sql Site Cache table, from which a new site is created
=cut

sub _action_order_site {
    my $session = shift;
    require Foswiki::Plugins::AccountsPlugin::Sites;
    Foswiki::Plugins::AccountsPlugin::Sites::order_site($session);
}

sub _action_refresh_sites {
	my $session = shift;
	my $request = $session->{'request'};
	unless($Foswiki::cfg{SiteName} eq 'tokyo.e-flamingo.net' && $session->{webName} eq 'Coverage'){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
	require Foswiki::Plugins::AccountsPlugin::Sites;
	Foswiki::Plugins::AccountsPlugin::Sites::refresh_sites($session);
}

# create's the site, but does not activate it (b/c of the Links, MPH tables, etc)
sub _action_create_site {
	my $session = shift;
	my $request = $session->{'request'};
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net' && $session->{'user'} eq $Foswiki::cfg{AdminUserKey}){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
	
	require Foswiki::Plugins::AccountsPlugin::Sites;
	Foswiki::Plugins::AccountsPlugin::Sites::create_site($session);
}
# activates the site after creation
sub _action_activate_site {
	my $session = shift;
	# this only runs if the product_id in the Sites table is NULL, otherwise this will save each topic once
	require Foswiki::Plugins::AccountsPlugin::Sites;
	Foswiki::Plugins::AccountsPlugin::Sites::activate_site($session);	
}
# activates the site after creation
sub _action_copy_site {
	my $session = shift;
	# this only runs if the product_id in the Sites table is NULL, otherwise this will save each topic once
	require Foswiki::Plugins::AccountsPlugin::Sites;
	Foswiki::Plugins::AccountsPlugin::Sites::copy_site($session);	
}
####################################################################################################################
=pod
---+ DiDs 
   1. refresh_dids - updates dataform database in tokyo.e-flamingo.net with new DiDs acquired into DiD inventory
   2. change_did_destination - used by the User to redirect DiD
   3. order_DiD - used by user to order a DiD
=cut

sub _action_refresh_dids {
	my $session = shift;
	my $request = $session->{'request'};
	unless($Foswiki::cfg{SiteName} eq 'tokyo.e-flamingo.net' && $session->{webName} eq 'Coverage'){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
	require Foswiki::Plugins::AccountsPlugin::DiDs;
	Foswiki::Plugins::AccountsPlugin::DiDs::refresh_dids($session);
}

sub _action_change_did_destination {
	my $session = shift;
	my $request = $session->{'request'};
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
	require Foswiki::Plugins::AccountsPlugin::DiDs;
	Foswiki::Plugins::AccountsPlugin::DiDs::change_did_destination($session);
}

# ordering DiD's
sub _action_order_DiD {
    my $session = shift;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
    require Foswiki::Plugins::AccountsPlugin::DiDs;
    Foswiki::Plugins::AccountsPlugin::DiDs::order_did($session);
}
####################################################################################################################
=pod
---+ Users 
The bottom is administrative
=cut

sub _action_refresh_user_base {
	my $session = shift;
	my $request = $session->{'request'};
	unless($Foswiki::cfg{SiteName} eq 'tokyo.e-flamingo.net' && $session->{webName} eq 'Coverage'){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
	require Foswiki::Plugins::AccountsPlugin::Users;
	Foswiki::Plugins::AccountsPlugin::Users::refresh_user_base($session);
}
# users update their information on e-flamingo.net
sub _action_user_self_update {
	my $session = shift;
	my $request = $session->{'request'};
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
	            throw Foswiki::OopsException(
                'attention',
                def    => 'unrecognized_action',
                params => ['refresh_user_base']
            );
	}
	require Foswiki::Plugins::AccountsPlugin::Users;
	#Foswiki::Plugins::AccountsPlugin::Users::user_self_update($session);
}

# a user can update their information on any site
# this function should be somewhere else (perhaps in the User part of Foswiki)
sub _action_change_user_config {
	my $session = shift;
	my $request = $session->{'request'};
	require Foswiki::Plugins::AccountsPlugin::Users;
	Foswiki::Plugins::AccountsPlugin::Users::change_user_config($session);
}

####################################################################################################################


1;
__END__

After the script is done, redirect here

        my $viewURL = $session->getScriptUrl( 1, 'view', $w, $t );
        $session->redirect( $session->redirectto($viewURL), undef, 1 );


