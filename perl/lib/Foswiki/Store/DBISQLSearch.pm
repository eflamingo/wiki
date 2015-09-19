# See bottom of file for license and copyright information
package Foswiki::Store::DBISQLSearch;

=pod TML

Using DBI to run queries.


=cut

use strict;
use warnings;
use Assert;

use Foswiki::Search::InfoCache;

use Foswiki::Contrib::DBIStoreContrib::TopicHandler ();
use Foswiki::Store::Interfaces::SearchAlgorithm ();
#@ISA = ( 'Foswiki::Store::Interfaces::SearchAlgorithm' );

# Implements Foswiki::Store::Interfaces::SearchAlgorithm
sub query {
    my ( $query, $inputTopicSet, $session, $options ) = @_;

    if ( $query->isEmpty() ) {
        return new Foswiki::Search::InfoCache( $session, '' );
    }
	# get the web keys
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler->new();
	# returns a Foswiki::Contrib::DBIStoreContrib::ResultSet object
	
    
    return $topic_handler->WordSearch($query, $inputTopicSet, $session, $options);	
}


1;
__END__