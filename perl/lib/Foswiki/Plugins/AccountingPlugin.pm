package Foswiki::Plugins::AccountingPlugin;

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
$pluginName        = 'AccountingPlugin';

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
    $Foswiki::cfg{SwitchBoard}{accounting} = {
        package  => 'Foswiki::UI::Accounting',
        function => 'accounting',
        context  => { accounting => 1 },
        allow    => { POST => 1, GET => 1 }
    };
    

	my $src = $Foswiki::Plugins::SESSION->{prefs}->getPreference('FWSRC') || '';
	#Foswiki::Func::registerTagHandler( 'ORDER', \&HandleOrderTag );

    return 1;
}

# handle order tags
sub commonTagsHandler {
	$_[0]  =~ s/%BALANCE(?:{(.*?)})?%/&handlerBalanceTag($_[2] ,$_[1] , $1)/geo;
	$_[0]  =~ s/%SPLIT(?:{(.*?)})?%/&handlerSplitTag($_[2] ,$_[1] , $1)/geo;
}
sub handlerBalanceTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountingPlugin::Ledger;
	return Foswiki::Plugins::AccountingPlugin::Ledger::balance_tag_renderer($inWeb,$inTopic, $args);
}

sub handlerSplitTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::AccountingPlugin::Ledger;
	return Foswiki::Plugins::AccountingPlugin::Ledger::split_tag_renderer($inWeb,$inTopic, $args);
}

1;
