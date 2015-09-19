# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Contrib::DBIStoreContrib::ResultSet

This class implements the ResultSet API - its basically a Sorted Aggregate Iterator for foswiki 1.1
   * NOTE: does not implement the unique function - by its nature, the data is unique, and it would be a non-trivial drain on memory in this context

Designed to work with DBI fetch

=cut

package Foswiki::Contrib::DBIStoreContrib::ResultSetAttachment;
use strict;
use warnings;

use Foswiki::Iterator ();
use Foswiki::Search::InfoCache;




=begin TML

---++ new($topic_handler,$selectStatement)

Create a new iterator over the given list of iterators. The list is
not damaged in any way.

=cut

sub new {
    my ($class, $array_ref ) = @_;
	
	
	# rowRefGuide 
	# {topic_history_key =>1, key => 1, topic_key => 2, version => 3, timestamp_epoch=> 4,
		#           user_key => 5, file_name => 6, file_type => 7, attachment_key => 8, comment => 9, file_blob => 10, size=> 11, revision => 3 };
	my $rowHash = {topic_history_key =>1, key => 1, topic_key => 2, version => 3, timestamp_epoch=> 4,
		user_key => 5, file_name => 6, file_type => 7, attachment_key => 8, comment => 9, file_blob => 10, size=> 11, revision => 3 };
	my $this = bless( 
	{RowNumber => scalar(@$array_ref), currentRow => undef,  currentRowNumber => -1, rowRefGuide => $rowHash, TopicMetaObject => undef, ReturnArray => $array_ref },
	$class);


    return $this;
}

# only initialize with a simple @list
sub newSimple {
	my ($class,$array_ref) = @_;
	
}


sub numberOfAttachments {
    my $this = shift;
    return $this->{RowNumber};
    
}

=begin TML

---++ hasNext() -> $boolean

Iterates to the next row.  Returns false when the iterator is exhausted. 

=cut

sub hasNext {
    my $this = shift;
	my $int = $this->{currentRowNumber};
	$int += 1;
	$this->{currentRow} = $this->{ReturnArray}->[$int];
	return undef unless $this->{currentRow};
	$this->{currentRowNumber} = $int;
    return 1;
}

=begin TML

---++ currentRow('topic_name') -> $ref to topic_history row
# 1-key/topic_history_key, 2-topic_key, 3-revision, 4-timestamp_epoch, 5-web_key, 6-topic_name, 7-summary, 8-web_name, 9-user_key, 10-permissions
Return the next entry in the list.

=cut

sub currentRow {
		my $this = shift;
		my $fieldname = shift;
		return undef unless $fieldname;
		my $int = $this->{rowRefGuide}->{$fieldname};
		if($int){
			$int -= 1;	
			# 1-key/topic_history_key, 2-topic_key, 3-revision, 4-timestamp_epoch, 5-web_key, 6-topic_name, 7-summary, 8-web_name, 9-user_key, 10-permissions
			return $this->{currentRow}->[$int];
		}
		elsif($fieldname eq 'wikiusername'){
			# TODO: need to call something, for now, just return the user key
			return $this->currentRow('user_key');
			
		}
		elsif($fieldname eq 'attr'){
			my $ext = $this->currentRow('file_type');
			return $this->getAttrFromExt($ext);
		}
				
}

=begin TML

---++ checkPermission('VIEW', $cUID) -> 0 or 1 depending on permissions

Checks to see if the user has VIEW permissions.

=cut

sub checkPermission {
	my ($this,$mode,$cUIDPlusMembers) = @_;
	$mode ||= 'VIEW';
	#return undef unless $cUIDPlusMembers;
	return 1;
	# do the checking here
	# 1 for can view, 0 for can't view, 'NULL' for if nothing is there
	#my $permissions = $this->currentRow('ALLOWTOPIC'.$mode);
}

=begin TML

---++ getCurrentTopicObj() -> Meta Object built from current Topic Row

Checks to see if the user has VIEW permissions.

=cut

sub getCurrentTopicObj {
	my $this = shift;
	my $session = shift;
	my $topicObject = $this->{TopicMetaObject};
	
	return undef unless defined($this->{currentRow}); 
	if( defined($topicObject) && $topicObject->web eq $this->currentRow('web_name') && $topicObject->topic eq $this->currentRow('topic_name') ) {
		return $topicObject;
	}
	# the rest assumes that the Meta object does not match the current row
	$this->{TopicMetaObject} = undef;
	$this->{TopicMetaObject} = new Foswiki::Meta($session,$this->currentRow('web_name'),$this->currentRow('topic_name'));
	$this->{TopicMetaObject}->text($this->currentRow('topic_content_summary'));
	# set the Topic Info
	my %info;
	$info{date} = $this->currentRow('timestamp_epoch');
    $info{author} = $this->currentRow('user_key');
	$info{version} = $this->currentRow('revision');
	$this->{TopicMetaObject}->setRevisionInfo(%info);
	return $this->{TopicMetaObject};
}

sub getAttrFromExt {
	my ($this,$ext) = @_;
	# .gif .png .doc. .xls
	return 'EXT';
}

1;
__END__