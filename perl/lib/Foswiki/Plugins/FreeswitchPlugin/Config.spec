# ---+ Extensions
# ---++ FreeswitchPlugin
# **PERL H**
# This setting is required to enable executing the sip script from the bin directory
$Foswiki::cfg{SwitchBoard}{query} = {
    package  => 'Foswiki::UI::Sip',
    function => 'sip',
    context  => { sip => 1,
                },
    };
1;