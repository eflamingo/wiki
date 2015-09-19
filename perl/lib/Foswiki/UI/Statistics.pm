# See bottom of file for license and copyright information

=pod TML

---+ package Foswiki::UI::Statistics

Statistics extraction and presentation

=cut

package Foswiki::UI::Statistics;

use strict;
use warnings;
use Assert;
use File::Copy qw(copy);
use IO::File ();
use Error qw( :try );

use Foswiki                         ();
use Foswiki::Sandbox                ();
use Foswiki::UI                     ();
use Foswiki::WebFilter              ();
use Foswiki::Time                   ();
use Foswiki::Meta                   ();
use Foswiki::AccessControlException ();

BEGIN {

    # Do a dynamic 'use locale' for this module
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

=pod TML

---++ StaticMethod statistics( $session )

=statistics= command handler.
This method is designed to be
invoked via the =UI::run= method.

Generate statistics topic.
If a web is specified in the session object, generate WebStatistics
topic update for that web. Otherwise do it for all webs

=cut

sub statistics {
	my $session = shift;

	my $tmp = '';
	require Foswiki::Meta;
	my $topicObject = Foswiki::Meta->new( $session, 'Main', 'WebHome' );
	$topicObject->saveToTar();

}


1;
__END__
