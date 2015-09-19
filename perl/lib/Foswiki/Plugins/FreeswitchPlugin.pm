package Foswiki::Plugins::FreeswitchPlugin;

# Always use strict to enforce variable scoping
use strict;

require Foswiki::Func;       # The plugins API
require Foswiki::Plugins;    # For the API version

require JSON;

use vars
  qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug $pluginName $NO_PREFS_IN_TOPIC );
$VERSION           = '1';
$RELEASE           = '1.0-a';
$SHORTDESCRIPTION  = 'Interface between Freeswitch server and Foswiki';
$NO_PREFS_IN_TOPIC = 1;
$pluginName        = 'FreeswitchPlugin';

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
    $Foswiki::cfg{SwitchBoard}{sip} = {
        package  => 'Foswiki::UI::Sip',
        function => 'sip',
        context  => { sip => 1 },
        allow    => { POST => 1 }
    };
    

	my $src = $Foswiki::Plugins::SESSION->{prefs}->getPreference('FWSRC') || '';


    return 1;
}

# handle order tags
sub commonTagsHandler {
	$_[0]  =~ s/%PHONECDR(?:{(.*?)})?%/&handlerPhoneTag($_[2] ,$_[1] , $1)/geo;
}
sub handlerPhoneTag {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins::FreeswitchPlugin::CDR;
	return Foswiki::Plugins::FreeswitchPlugin::CDR::PhoneCDRRenderer($inWeb,$inTopic, $args);
}

1;
