package Foswiki::Plugins::AccountsPlugin;

# Always use strict to enforce variable scoping
use strict;

require Foswiki::Func;       # The plugins API
require Foswiki::Plugins;    # For the API version

require JSON;

use vars
  qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug $pluginName $NO_PREFS_IN_TOPIC );
$VERSION           = '1';
$RELEASE           = '1.0-a';
$SHORTDESCRIPTION  = 'Interface between the business backend and Foswiki';
$NO_PREFS_IN_TOPIC = 1;
$pluginName        = 'AccountsPlugin';

# ---------------Caching-----------------------
my $cache = { 'orders' => {}, 'contracts' => {}};
sub getOrder {
	my $order_key = shift;
	return $cache->{'orders'}->{$order_key};
}
sub setOrder {
	my $order_obj = shift;
	return $cache->{'orders'}->{$order_obj->key} = $order_obj;
}
# ---------------Plugin Stuff-----------------------
sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between $pluginName and Plugins.pm");
        return 0;
    }

    $debug = $Foswiki::cfg{Plugins}{RestPlugin}{Debug} || 0;

    #tell Foswiki::UI about the new handler.
    $Foswiki::cfg{SwitchBoard}{accounts} = {
        package  => 'Foswiki::UI::Accounts',
        function => 'accounts',
        context  => { accounts => 1 },
        allow    => { POST => 1, GET => 1 }
    };
    

	my $src = $Foswiki::Plugins::SESSION->{prefs}->getPreference('FWSRC') || '';
	#Foswiki::Func::registerTagHandler( 'ORDER', \&HandleOrderTag );

    return 1;
}

# handle order tags
sub commonTagsHandler {
	$_[0]  =~ s/%ORDER(?:{(.*?)})?%/&handlerOrderTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%ORDERSEARCH(?:{(.*?)})?%/&handlerOrderSearchTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%USERDETAIL(?:{(.*?)})?%/&handlerUserTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%DIDSEARCH(?:{(.*?)})?%/&handlerDiDSearchTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%SITESEARCH(?:{(.*?)})?%/&handlerSiteSearchTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%DIDINFO(?:{(.*?)})?%/&handlerDiDInfoTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%SITEINFO(?:{(.*?)})?%/&handlerSiteInfoTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%CREDITBALANCE(?:{(.*?)})?%/&handlerCreditBalanceTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%CREDITHISTORY(?:{(.*?)})?%/&handlerCreditHistoryTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%BITCOIN(?:{(.*?)})?%/&handlerBitcoinTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%SITEMANMONTHS(?:{(.*?)})?%/&handlerSiteManMonthsTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%DWOLLAPAY(?:{(.*?)})?%/&handlerDwollaPayTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%BITCOINORDER(?:{(.*?)})?%/&handlerBitCoinOrderTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%DIDPROVIDER1(?:{(.*?)})?%/&handleriCallAPITag($_[2] ,$_[1] , $1)/geo;
}
sub handlerOrderTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Orders;
	return Foswiki::Plugins::AccountsPlugin::Orders::order_tag_renderer($inWeb,$inTopic, $args);
}

sub handlerOrderSearchTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Orders;
	return Foswiki::Plugins::AccountsPlugin::Orders::search_tag_renderer($inWeb,$inTopic, $args);
}

sub handlerCreditBalanceTag {
	my ($inWeb,$inTopic, $args) = @_;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return ' ';
	}
	require Foswiki::Plugins::AccountsPlugin::Credits;
	return Foswiki::Plugins::AccountsPlugin::Credits::get_credit_balance($inWeb,$inTopic, $args);
}
sub handlerCreditHistoryTag {
	my ($inWeb,$inTopic, $args) = @_;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return ' ';
	}
	require Foswiki::Plugins::AccountsPlugin::Credits;
	return Foswiki::Plugins::AccountsPlugin::Credits::get_credit_history($inWeb,$inTopic, $args);
}

sub handlerUserTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Users;
	return Foswiki::Plugins::AccountsPlugin::Users::user_info($inWeb,$inTopic, $args);
}

sub handlerDiDSearchTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::DiDs;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return ' ';
	}
	return Foswiki::Plugins::AccountsPlugin::DiDs::did_search($inWeb,$inTopic, $args);
}

sub handlerSiteSearchTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Sites;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return ' ';
	}
	return Foswiki::Plugins::AccountsPlugin::Sites::site_search($inWeb,$inTopic, $args);
}

sub handlerSiteManMonthsTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Sites;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return '';
	}
	return Foswiki::Plugins::AccountsPlugin::Sites::site_man_hours($inWeb,$inTopic, $args);
}
sub handlerBitcoinTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Users;
	return Foswiki::Plugins::AccountsPlugin::Users::bitcoin($inWeb,$inTopic, $args);
}

sub handlerDiDInfoTag {
	my ($inWeb,$inTopic, $args) = @_;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return '';
	}
	require Foswiki::Plugins::AccountsPlugin::DiDs;
	return Foswiki::Plugins::AccountsPlugin::DiDs::did_info($inWeb,$inTopic, $args);
}
sub handlerSiteInfoTag {
	my ($inWeb,$inTopic, $args) = @_;
	unless($Foswiki::cfg{SiteName} eq 'e-flamingo.net'){
		return ' ';
	}
	require Foswiki::Plugins::AccountsPlugin::Sites;
	return Foswiki::Plugins::AccountsPlugin::Sites::site_info($inWeb,$inTopic, $args);
}
sub handlerDwollaPayTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Orders;
	return Foswiki::Plugins::AccountsPlugin::Orders::dwolla_pay($inWeb,$inTopic, $args);
}


sub handlerBitCoinOrderTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::Orders;
	return Foswiki::Plugins::AccountsPlugin::Orders::bitcoin_order($inWeb,$inTopic, $args);
}

sub handleriCallAPITag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountsPlugin::iCall;
	return Foswiki::Plugins::AccountsPlugin::iCall::display($inWeb,$inTopic, $args);
}

1;
