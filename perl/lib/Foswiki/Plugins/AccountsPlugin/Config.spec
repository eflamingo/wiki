# ---+ Extensions
# ---++ AccountsPlugin
# **PERL H**
# This setting is required to enable executing the sip script from the bin directory
$Foswiki::cfg{SwitchBoard}{query} = {
    package  => 'Foswiki::UI::Accounts',
    function => 'accounts',
    context  => { accounts => 1,
                }
    };
1;