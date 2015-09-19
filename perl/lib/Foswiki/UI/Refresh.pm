# See bottom of file for license and copyright information
package Foswiki::UI::Refresh;

=pod TML

---+ package Foswiki::UI::Refresh

Refreshes the cache on a per site basis

=cut

use strict;
use warnings;
use Assert;
use Error qw( :try );

use Foswiki                ();
use Foswiki::UI            ();
use Foswiki::OopsException ();
use Foswiki::Form          ();

=pod TML

---++ StaticMethod refresh( $session )

Refresh the cache.

=cut

sub refresh {
    my $session = shift;
    run_refresh($session);
}

sub run_refresh {
    my ( $session, $templateName ) = @_;
    my $query = $session->{request};
    my $web   = $session->{webName};
    my $topic = $session->{topicName};
    my $user  = $session->{user};
    my $users = $session->{users};
    
    # Delta
	_l2l_webs();
	_l2l_topics();
	_l2l_attachments(); 
    
    
}
=pod
---+ Delta
This keeps link_to_latest up to date.
   * [[http://www.perlmonks.org/?node_id=510202]]
#Save
use Data::Dumper;
$Data::Dumper::Purity = 1;
open FILE, ">$outfile" or die "Can't open '$outfile':$!";
print FILE Data::Dumper->Dump([$main], ['*main']);
close FILE;
#restore
open FILE, $infile;
undef $/;
eval <FILE>;
close FILE;

=cut

=pod
---++ l2l_webs

=cut
sub _l2l_webs {
	# find all of the webs.
	my $session = shift;
	my $topicObject = Foswiki::Meta->new( $session, $web, $topic );
	$topicObject->refreshCache($session,'l2l_webs');
}

=pod
---++ l2l_topics

=cut

sub _l2l_topics {
	my $session = shift;
	my $topicObject = Foswiki::Meta->new( $session, $web, $topic );
	$topicObject->refreshCache($session,'l2l_topics');	
	
}
=pod
---++ _l2l_attachments

=cut
sub _l2l_attachments {
	
	my $session = shift;
	my $topicObject = Foswiki::Meta->new( $session, $web, $topic );
	$topicObject->refreshCache($session,'l2l_attachments');	
}

sub return_page {

    my ( $session, $topicObject, $tmpl ) = @_;

    my $query = $session->{request};
=pod
    # apptype is deprecated undocumented legacy
    my $cgiAppType =
         $query->param('contenttype')
      || $query->param('apptype')
      || 'text/html';

    my $text = $topicObject->text() || '';
    $tmpl =~ s/%UNENCODED_TEXT%/$text/g;

    $text = Foswiki::entityEncode($text);
    $tmpl =~ s/%TEXT%/$text/g;

    $topicObject->setLease( $Foswiki::cfg{LeaseLength} );

    $session->writeCompletePage( $tmpl, 'edit', $cgiAppType );
=cut
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 1999-2007 Peter Thoeny, peter@thoeny.org
and TWiki Contributors. All Rights Reserved. TWiki Contributors
are listed in the AUTHORS file in the root of this distribution.
Based on parts of Ward Cunninghams original Wiki and JosWiki.
Copyright (C) 1998 Markus Peter - SPiN GmbH (warpi@spin.de)
Some changes by Dave Harris (drh@bhresearch.co.uk) incorporated

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
