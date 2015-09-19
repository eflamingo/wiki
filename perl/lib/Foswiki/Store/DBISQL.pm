# See bottom of file for license and copyright information

=pod

---+ package Foswiki::Store::DBISQL

Implementation of =Foswiki::Store= for stores that use the DBI cpan module
to manage an SQL database. 

=cut

package Foswiki::Store::DBISQL;



use strict;
use warnings;
use diagnostics -verbose;

use Assert;
use Error qw( :try );
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use File::Basename ();
#use Test::utf8 ();

use Foswiki          ();
use Foswiki::Meta    ();
use Foswiki::Sandbox ();
use Foswiki::Iterator::NumberRangeIterator ();
use Foswiki::OopsException ();
use Foswiki::Form ();
use Foswiki::Store() ;
our @ISA = qw( Foswiki::Store );


use Foswiki::Contrib::DBIStoreContrib::Handler();
use Foswiki::Contrib::DBIStoreContrib::TopicHandler();
use Foswiki::Contrib::DBIStoreContrib::WebHandler();

use Foswiki::Contrib::DBIStoreContrib::AttachmentHandler();
use Foswiki::Contrib::DBIStoreContrib::LinkHandler();
use Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler();
use Foswiki::Contrib::DBIStoreContrib::DataformHandler();


# extra stuff used in the save listener
#use Foswiki::Plugins::AccountsPlugin::Credits();


BEGIN {

    # Do a dynamic 'use locale' for this module
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}


############################################################################################
########################                Listeners               ############################
############################################################################################

my @TopicSubsetHandlers = (
	\&Foswiki::Contrib::DBIStoreContrib::LinkHandler::listener,
	\&Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::listener,
	\&Foswiki::Contrib::DBIStoreContrib::DataformHandler::listener,
	\&Foswiki::Contrib::DBIStoreContrib::AttachmentHandler::listener,
	#\&Foswiki::Plugins::AccountsPlugin::Credits::listener
);
# run the listeners based
# The site handler must be passed as the first variable
# The name of the function calling the listeners must be passed as the second variable
# runListener('saveTopic',$sourcefunc,@vars)
sub runListeners {
	my $this = shift;
	my $sourcefunc = shift;
	my @vars = @_; # the rest of the variables

	foreach my $listener (@TopicSubsetHandlers) {
		#die "Listener: $listener running $handle_listeners{$listener} Function\n";
		$listener->($this->{site_handler},$sourcefunc,@vars);
	}

}

############################################################################################
########################             Constructor/Destructor          ############################
############################################################################################

sub new {
	my ( $class ) = shift;
	my $this = Foswiki::Store::->new();
	bless $this, $class;

	# find out what the site key is for future reference
	$this->{site_handler} = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $site_handler = ref($this->{site_handler});
	#print "creating dbi store\n Ref: $site_handler";
	return $this;
}


sub finish {
	my $this = shift;
	#print "dbi::finish()\n";
	#$this->{site_handler}->finish();
	undef $this->{site_handler};
	return 1;
}

sub eachTopic {
	my $this = shift;
	my $web_name = shift;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	return $topic_handler->eachTopic($web_name);
=pod	
	my $return_hash = $topic_handler->eachTopic($web_name);
	my @list = values(%$list_ref);

	# be nice and put this in the cache
	foreach( my $topic_key keys(%return_hash)) {
		#$topic_handler->putTopicKeyByWT($web_name,$list_ref->{$return_hash->{$topic_key}},$topic_key);
	}

	@list = sort(@list);
	require Foswiki::ListIterator;
	return new Foswiki::ListIterator( \@list );
=cut
}

sub createNewWeb {
	my $this = shift;

	my ($session, $new_web_name ) = @_;
	my $site_key = $this->{site_handler}->{site_key};
	my $user_key = $session->{user};

	# All the topics that are necessary for making a new web
	my $app = 'WebBuilder';
	my $lang = 'English';
	## Generate Webs row for Insert ##
	my %websRow;
	my %WHRow;

	# generate some key for the web
	my $new_web_key = $this->{site_handler}->createUUID();
	$websRow{key} = $new_web_key;
	$websRow{link_to_latest} = '00000000-0000-0000-0000-000000000000';
	$websRow{current_web_name} = $new_web_name;
	$websRow{site_key} = $site_key;
	$websRow{web_preferences} = '';
	$websRow{web_home} = '';
	$websRow{timestamp_epoch} = time();
	$websRow{user_key} = $user_key;
	$websRow{web_name} = $websRow{current_web_name};

	# MetaPreferenceHandler inherits from the TopicHandler
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::->init($this->{site_handler});

	######### Start Transaction ############
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;

	eval{

		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();	
		## load the Topics first ##
		my @newTopics = keys %{ $Foswiki::cfg{$app}{$lang} };

		foreach my $defTopic (@newTopics) {
			# create a new topic row
			my %topicRow;
			$topicRow{key} = $this->{site_handler}->createUUID();
			my %throw;
			$throw{topic_key} = $topicRow{key};
			$throw{timestamp_epoch} = time();
			$throw{topic_name} = $defTopic;
			$throw{topic_content} = $Foswiki::cfg{$app}{$lang}{$defTopic};
			$throw{web_key} = $new_web_key;
			$throw{revision} = 1;
			$throw{user_key} = $user_key;

			$throw{topic_name_key} = $topic_handler->insert_Blob_Store($throw{topic_name});
			$throw{topic_content_key} = $topic_handler->insert_Blob_Store($throw{topic_content});
			my $new_th_row_key = $topic_handler->insertTHRow(\%throw);
			$throw{key} = $new_th_row_key;
			# insert the topic row in case this is a new topic
			$topicRow{link_to_latest} = $throw{key};
			$topicRow{current_web_key} = $throw{web_key};
			$topicRow{current_topic_name} = $throw{topic_name_key};
			$topic_handler->insertTopicRow(\%topicRow);		

			$websRow{web_home} = $topicRow{key} if $defTopic eq 'WebHome';
			$websRow{web_preferences} = $topicRow{key} if $defTopic eq 'WebPreferences';
	
			# rip the Meta Preferences Out, we need them later
			my @prefs = @{Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::_extractPrefFromText($throw{topic_content})};
			my %doublePref;
			# 'type' => $type, 'name' => $key, 'value' => $value 
			foreach my $pref (@prefs) {
				$pref->{topic_history_key} = $new_th_row_key;
				my ($temptype,$tempname,$tempvalue) = ($pref->{type},$pref->{name},$pref->{value});
				$topic_handler->insert_MP($pref) unless $doublePref{$defTopic.$temptype.$tempname.$tempvalue};
				$doublePref{$defTopic.$temptype.$tempname.$tempvalue} = 1;
			}
	
		}

		# Insert the web
		my $web_handler = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::WebHandler;
		$web_handler->insertNewWeb(\%websRow);
		$topic_handler = bless $web_handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
		#### Transaction Finished, Commit! ####
		$topic_handler->database_connection()->commit;

	};
	if ($@) {

		warn "Rollback - failed to create ($new_web_name) for reason:\n $@";
		$topic_handler->database_connection()->errstr;

		eval{
			$topic_handler->database_connection()->rollback;
		};

	}



	# change it to autocommit after the transaction is done	
	$topic_handler->database_connection()->{AutoCommit} = 1;
	bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::Handler;


}


sub readTopic {
	my ($this,$topicObject, $version ) = @_;
	my ($topic_name,$web_name) = ( $topicObject->topic(),$topicObject->web() );
	#print "dbi::readTopic()\n";
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});

	my $isLatest = 0;
	my $gotRev = 1;
	
	

	# check local cache
	my $lthrow;
	$lthrow = $topic_handler->LoadTHRow($web_name,$topic_name,$version);
	if($lthrow->{key}){
		
		my $setembeddtext = $topic_handler->fetchMemcached('metaobject_cache',$lthrow->{key});
		$topicObject->setEmbeddedStoreForm( $setembeddtext ) if $setembeddtext;
	
		$gotRev = $lthrow->{revision};
		$gotRev = $version if $version;
		$isLatest = 1 if !$version;
		return ($gotRev, $isLatest) if $setembeddtext;
	}
	
	# get the topic data from Topics 
	my $topic_row;
	if($version){
		$topic_row = $topic_handler->LoadTHRow($web_name,$topic_name,$version);
	}
	else{
		$topic_row = $topic_handler->LoadTHRow($web_name,$topic_name);
	}
	my $temp_key = $topic_row->{topic_key};
	# need to get the blob values from the Blob_Store
	my @array_of_keys = ($topic_row->{topic_content_key},$topic_row->{topic_name_key});
	my %blob_values = %{ $topic_handler->get_blob_value( @array_of_keys ) };
	# TODO: getting lots of errors here
	$topic_row->{topic_content} = $blob_values{$topic_row->{topic_content_key}} if $topic_row->{topic_content_key};
	$topic_row->{topic_name} = $blob_values{$topic_row->{topic_name_key}} if $topic_row->{topic_name_key};
	my $test_topic_content = $topic_row->{topic_content};
	#print "web,topic: ($web_name,$topic_name)\n" unless $test_topic_content;

	# since topics are UUID based, get the topic key
	my $t_h_key = $topic_row->{topic_history_key};
	return (undef, $isLatest) unless defined $t_h_key;

	# set the topicObject data

	$topicObject->text($topic_row->{topic_content});
	# set the Topic Info
	my %info;
	$info{date} = $topic_row->{timestamp_epoch};
        $info{author} = $topic_row->{user_key};
	$info{version} = $topic_row->{revision};
	$topicObject->setRevisionInfo(%info);

	my @varsForListeners = ($topicObject,$topic_row);
	$this->runListeners('readTopic',@varsForListeners);


	# Part 2: Get the form data	
	## this code only works if there is only 1 form attached per topic
	#$meta->put( 'FIELD', { name => 'MaxAge', title => 'Max Age', value =>'103' } );
	#$meta->put( 'FORM', { name => 'PatientForm' } );
	#my $form_data = $topic_handler->LoadFormData();



	
	# load the meta object into Memcached

	my $vx = $version if $version;
	$vx = '-1' unless $version;
	$lthrow = $topic_handler->LoadTHRow($web_name,$topic_name,$version);
	$topic_handler->putMemcached('metaobject_cache',$lthrow->{key},$topicObject->getEmbeddedStoreForm(),60);

	$gotRev = $topic_row->{revision};
	$gotRev = $version if $version;
	$isLatest = 1 if !$version;

	return ($gotRev, $isLatest);
}
=pod
---++ readTopicsByTHKeys(\@arrayOfTHKeys) -> \@arrayOfMetaObjects
This function is for use with ResultSet
=cut

sub readTopicsByTHKeys {
	my ($this,$input_th_key_ref ) = @_;
	my @arraythkeys = @{$input_th_key_ref};
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	$topic_handler->LoadTHRowFromTHKey($arraythkeys[0]);
	
	
}



=pod TML

---++ ObjectMethod moveTopic(  $oldTopicObject, $newTopicObject, $cUID ,\%opts )

All parameters must be defined and must be untainted.

Implementation must invoke 'update' on event listeners.

=cut

sub moveTopic {
    my ( $this, $oldTopicObject, $newTopicObject, %opts ) = @_;
	my $cUID = $opts{user};

	my ($oldWeb,$oldTopic) = ($oldTopicObject->web,$oldTopicObject->topic);
	my ($newWeb,$newTopic) = ($newTopicObject->web,$newTopicObject->topic);
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	my $site_key = $topic_handler->{site_key};

	#die "Move:  ($oldWeb, $oldTopic) => ($newWeb, $newTopic)\n";

	# load the old row so we can calculate the new th_key without having to query the database
	my $new_row = $topic_handler->LoadTHRow($oldWeb,$oldTopic);

	my $oldthkey = $new_row->{key};

	# db prep, turn off autocommits so we can use transactions
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;

	eval{

		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();
		$new_row->{web_key} = $topic_handler->getWebKey($newWeb);
		$new_row->{topic_name_key} = $topic_handler->insert_Blob_Store($newTopic);
		
		$new_row->{user_key} = $cUID;
		# calculate the new topic_name_key and web_key	
		my $newthkey = $topic_handler->insertTHRow($new_row);
			# Run all of the listeners (2nd pass, inserting takes place)
		$this->runListeners('moveTopic',$oldthkey,$newthkey);
		# attempt to commit all of the changes (be aware that constraints have been deferred)
		$topic_handler->database_connection()->commit;

	};
	if ($@) {
		warn "Rollback - failed to save ($newWeb,$newTopic) for reason:\n $@";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}
	


	# change it to autocommit after the transaction is done	
	$topic_handler->database_connection()->{AutoCommit} = 1;



}
=pod
---++ refreshCache ($meta_object, $type)
Refreshes cache.  It is called from /bin/refresh script, which then calls meta->refreshCache()
=cut

sub refreshCache {
	my ($this,$metaobj,$type) = @_;
	# l2l_webs
	# l2l_topics
	# l2l_attachments	
}

=pod TML

---++ ObjectMethod  moveAttachment( $this, $name, $to, $newName, $cUID )

All parameters must be defined and must be untainted.

Implementation must invoke 'update' on event listeners.

=cut

sub moveAttachment {
    my ( $this, $name, $to, $newName, $cUID ) = @_;
    my ($old_web,$old_topic) = ($this->web,$this->topic);
    my ($new_web,$new_topic) = ($to->web,$to->topic);
    my ($old_attachment,$new_attachment) = ($name,$newName);
    
}

sub topicExists {
	my ( $this, $web, $topic ) = @_;
	
	#print "dbi::topicExists()\n";
	return 0 unless defined $web && $web ne '';
	$web =~ s#\.#/#go;
	return 0 unless defined $topic && $topic ne '';
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	# first, test the cache	
	my $topic_key = $topic_handler->fetchTopicKeyByWT($web,$topic);
	# use this as an opportunity to load a topic and stuff it in the cache.
	my $row_ref = $topic_handler->LoadTHRow($web,$topic) unless $topic_key;
	return 0 unless $row_ref->{topic_history_key} || $topic_key;
	return 1;
}

# ($topic_key)->"$web.$topic"
sub getWTFromTopicKey {
	my ( $this, $topic_key ) = @_;

	return 0 unless defined $topic_key && $topic_key ne '';
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	# first, test the cache	
	my ($web,$topic) = $topic_handler->LoadWTFromTopicKey($topic_key);
	
	return undef unless $web && $topic;
	return ($web,$topic);

}

# ($th_key)->"$web,$topic,$rev"
sub getWTRFromTHKey {
	my ( $this, $th_key ) = @_;

	return 0 unless defined $th_key && $th_key ne '';
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	# function is slow b/c it does not seek memcache before going to the db
	my ($web,$topic,$rev) = $topic_handler->LoadWTRFromTHKey($th_key);
	
	return undef unless $web && $topic && $rev;
	return ($web,$topic,$rev);
}

sub getTopicKeyByWT {
	my $this = shift;
	my ($web,$topic) = @_;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	return $topic_handler->fetchTopicKeyByWT($web,$topic);
}

sub getTopicHistoryKeyByWTR {
	my $this = shift;
	my ($web,$topic,$revision) = @_;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	return $topic_handler->fetchTHKeyByWTR($web,$topic,$revision);
}

sub getRevisionHistory_Topic {
	my $this = shift;
	#print "dbi::getRevisionHistory()\n";
	my ($topicObject) = shift;
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	my $maxRev = $topic_handler->getLatestRevisionID_Topic($web_name,$topic_name);
	return new Foswiki::Iterator::NumberRangeIterator( $maxRev, 1 );
}

sub getRevisionHistory_Attachment {
	my $this = shift;
	my ($topicObject,$attachment_name) = @_;
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	my $attachment_handler = Foswiki::Contrib::DBIStoreContrib::AttachmentHandler::->init($this->{site_handler});
	# fetch the latest row
	my $ahrow = $attachment_handler->LoadAHRow($web_name,$topic_name,$attachment_name);
	#  ('key', 'topic_key', 'version', 'path', 'timestamp_epoch', 'user_key', 'attr', 'file_name', 'file_type', 
  	#				'blob_store_key', 'file_store_key', 'comment', 'attachment_key', 'size', 'file_blob');
	my $attachment_key = $ahrow->{attachment_key};
	my $array_ref = $attachment_handler->loadAllRevisionsByAttachmentKey($attachment_key);
	require Foswiki::Contrib::DBIStoreContrib::ResultSetAttachment;
	return new Foswiki::Contrib::DBIStoreContrib::ResultSetAttachment($array_ref);
}


sub getLatestRevisionID_Topic {
	my $this = shift;
	#print "dbi::getLatestRevisionID()\n";
	my ($web_name,$topic_name) = @_;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	return $topic_handler->getLatestRevisionID_Topic($web_name,$topic_name);
}

sub getLatestRevisionID_Attachment {
	my $this = shift;
	my ($topicObject,$attachment_name) = @_;
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	my $attachment_handler = Foswiki::Contrib::DBIStoreContrib::AttachmentHandler::->init($this->{site_handler});
	my $ahrow = $attachment_handler->LoadAHRow($web_name,$topic_name,$attachment_name);
	return $ahrow->{version};

}


=pod TML

---++ ObjectMethod saveTopic( $topicObject, $cUID, $options  ) -> $integer

Save a topic or attachment _without_ invoking plugin handlers.
   * =$topicObject= - Foswiki::Meta for the topic
   * =$cUID= - cUID of user doing the saving
   * =$options= - Ref to hash of options
=$options= may include:
   * =forcenewrevision= - force a new revision even if one isn't needed
   * =forcedate= - force the revision date to be this (epoch secs)
   * =minor= - True if this is a minor change (used in log)
   * =author= - cUID of author of the change

Returns the new revision identifier.

Implementation must invoke 'update' on event listeners.

=cut
sub saveTopic {
	my ( $this, $topicObject, $cUID, $options ) = @_;
	ASSERT( $topicObject->isa('Foswiki::Meta') ) if DEBUG;
	ASSERT($cUID) if DEBUG;
	
	# need to return info on the new topic revision
	my $th_row_ref;
	if($options->{'nocommit'}){
		# no eval
		$th_row_ref = $this->_saveTopic_no_eval($topicObject, $cUID, $options);
	}
	else{
		# eval
		$th_row_ref = $this->_saveTopic_eval($topicObject, $cUID, $options);
	}
	return $th_row_ref;
}

sub _saveTopic_eval {
	my ( $this, $topicObject, $cUID, $options ) = @_;
	ASSERT( $topicObject->isa('Foswiki::Meta') ) if DEBUG;
	ASSERT($cUID) if DEBUG;
	
	#print "Saving Topic!!!!!!!!\n";
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());

	# create a topic handler object
	my $scrap_handler = $options->{'handler'} || $this->{site_handler};
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($scrap_handler);
	# TODO: get rid of LoadTHRow; it is needed to make sure whether this is a new topic or an update of an old topic
	my $old_row = $topic_handler->LoadTHRow($web_name,$topic_name);

	# get topic key (if it does not exist, then this is a new topic)
	my $topic_key = $topic_handler->fetchTopicKeyByWT($web_name,$topic_name);
	# get last link_to_latest key
	my $old_th_key = $topic_handler->fetchTHKeyByWTR($web_name,$topic_name);
	my $topic_row_ref = $topic_handler->fetchTHRowByTHKey($old_th_key);
	my $new_topic_key;
	unless($topic_key){
		$new_topic_key = $topic_handler->createUUID() unless $topic_key; # incase this is a new topic
		$new_topic_key = $options->{'preseed_topic_key'} if $options->{'preseed_topic_key'};
	}
	

	# db prep, turn off autocommits so we can use transactions
	# that is unless $opts->{'nocommit'} = 1
	my $dontCommit = $options->{'nocommit'};
	
	
	# Run all of the listeners - (before setting AutoCommit to 0)
	$topic_handler->database_connection()->{AutoCommit} = 1;

	$this->runListeners('convertForSaveTopic',$topicObject,$cUID,$options);
	
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;

	my %th_row_ref;
	eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();

		# will use this to insert topic_history row
		
		$th_row_ref{topic_key} = $topic_key || $new_topic_key;
		$th_row_ref{user_key} = $cUID;
		$th_row_ref{web_key} = $this->{site_handler}->{web_cache}->{$web_name};
		$th_row_ref{web_name} = $web_name;
		$th_row_ref{timestamp_epoch} = time();
		$th_row_ref{topic_content} = $topicObject->text();
		$th_row_ref{topic_name} = $topic_name;
		$th_row_ref{revision} = $topic_row_ref->{revision} + 1 if $topic_row_ref->{revision};
		$th_row_ref{revision} = 1 unless $topic_row_ref->{revision};
		my ($content001) = $th_row_ref{topic_content};
		# utf8 test
		my @linebyline = split('\n',$content001);
		
		# check to see if we are just refreshing the subset tables only (metapreferences, links, etc)
		if($options->{'refreshTopic'}){
			# we don't save the topic itself, so no Topic_History or Topics inserts
			$this->runListeners('refreshTopic',$old_row->{key});
			$this->runListeners('saveTopic',$topicObject, $cUID,$old_row);
		}
		else{
			# First, upload the Blob stuff
			$th_row_ref{topic_name_key} = $this->{site_handler}->insert_Blob_Store($th_row_ref{topic_name});
			$th_row_ref{topic_content_key} = $this->{site_handler}->insert_Blob_Store($th_row_ref{topic_content});
			# Then, insert the topic_history row
			my $new_th_row_key = $topic_handler->insertTHRow(\%th_row_ref);
			$th_row_ref{key} = $new_th_row_key;
			# insert the topic row in case this is a new topic
			unless($topic_key){
				my %topic_row_ref;
				$topic_row_ref{key} = $th_row_ref{topic_key};
				# Topic_History trigger won't run b/c this is a new topic, so put in the th_row info
				$topic_row_ref{link_to_latest} = $new_th_row_key;
				$topic_row_ref{current_web_key} = $this->{site_handler}->{web_cache}->{$web_name};
				$topic_row_ref{current_topic_name} = $th_row_ref{topic_name_key};
				$topic_handler->insertTopicRow(\%topic_row_ref);

			}
			# Run all of the listeners (2nd pass, inserting takes place)
			$this->runListeners('saveTopic',$topicObject, $cUID,\%th_row_ref);
		}


		# attempt to commit all of the changes (be aware that constraints have been deferred)
		$topic_handler->database_connection()->commit;
	};
	if ($@) {
		warn "Rollback - failed to save ($web_name,$topic_name) for reason:\n $@";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}
	
	# change it to autocommit after the transaction is done	
	$topic_handler->database_connection()->{AutoCommit} = 1;

	return \%th_row_ref;
}
# _saveTopic_no_eval-> th_row_ref
sub _saveTopic_no_eval {
	my ( $this, $topicObject, $cUID, $options ) = @_;
	ASSERT( $topicObject->isa('Foswiki::Meta') ) if DEBUG;
	ASSERT($cUID) if DEBUG;
	
	#print "Saving Topic!!!!!!!!\n";
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());

	# create a topic handler object
	my $scrap_handler = $options->{'handler'} || $this->{site_handler};
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($scrap_handler);
	# TODO: get rid of LoadTHRow; it is needed to make sure whether this is a new topic or an update of an old topic
	my $old_row = $topic_handler->LoadTHRow($web_name,$topic_name);

	# get topic key (if it does not exist, then this is a new topic)
	my $topic_key = $topic_handler->fetchTopicKeyByWT($web_name,$topic_name);
	# get last link_to_latest key
	my $old_th_key = $topic_handler->fetchTHKeyByWTR($web_name,$topic_name);
	my $topic_row_ref = $topic_handler->fetchTHRowByTHKey($old_th_key);
	my $new_topic_key;
	unless($topic_key){
		$new_topic_key = $topic_handler->createUUID() unless $topic_key; # incase this is a new topic
		$new_topic_key = $options->{'preseed_topic_key'} if $options->{'preseed_topic_key'};
	}
	warn "New vs Old: $topic_key vs ($new_topic_key)";
	

	# db prep, turn off autocommits so we can use transactions
	# that is unless $opts->{'nocommit'} = 1
	my $dontCommit = $options->{'nocommit'};
	
	
	# Run all of the listeners - (before setting AutoCommit to 0)
	#$topic_handler->database_connection()->{AutoCommit} = 1 unless $dontCommit;

	$this->runListeners('convertForSaveTopic',$topicObject,$cUID,$options);
	
	#$topic_handler->database_connection()->{AutoCommit} = 0  unless $dontCommit;
	#$topic_handler->database_connection()->{RaiseError} = 1  unless $dontCommit;

	#eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred() unless $dontCommit;

		# will use this to insert topic_history row
		my %th_row_ref;
		$th_row_ref{topic_key} = $topic_key || $new_topic_key;
		$th_row_ref{user_key} = $cUID;
		$th_row_ref{web_key} = $this->{site_handler}->{web_cache}->{$web_name};
		$th_row_ref{web_name} = $web_name;
		$th_row_ref{timestamp_epoch} = time();
		$th_row_ref{topic_content} = $topicObject->text();
		$th_row_ref{topic_name} = $topic_name;
		$th_row_ref{revision} = $topic_row_ref->{revision} + 1 if $topic_row_ref->{revision};
		$th_row_ref{revision} = 1 unless $topic_row_ref->{revision};
		my ($content001) = $th_row_ref{topic_content};
		# utf8 test
		my @linebyline = split('\n',$content001);
		
		# check to see if we are just refreshing the subset tables only (metapreferences, links, etc)
		if($options->{'refreshTopic'}){
			# we don't save the topic itself, so no Topic_History or Topics inserts
			$this->runListeners('refreshTopic',$old_row->{key});
			$this->runListeners('saveTopic',$topicObject, $cUID,$old_row);
		}
		else{
			# First, upload the Blob stuff
			$th_row_ref{topic_name_key} = $this->{site_handler}->insert_Blob_Store($th_row_ref{topic_name});
			$th_row_ref{topic_content_key} = $this->{site_handler}->insert_Blob_Store($th_row_ref{topic_content});
			# Then, insert the topic_history row
			my $new_th_row_key = $topic_handler->insertTHRow(\%th_row_ref);
			$th_row_ref{key} = $new_th_row_key;
			# insert the topic row in case this is a new topic
			unless($topic_key){
				my %topic_row_ref;
				$topic_row_ref{key} = $th_row_ref{topic_key};
				# Topic_History trigger won't run b/c this is a new topic, so put in the th_row info
				$topic_row_ref{link_to_latest} = $new_th_row_key;
				$topic_row_ref{current_web_key} = $this->{site_handler}->{web_cache}->{$web_name};
				$topic_row_ref{current_topic_name} = $th_row_ref{topic_name_key};
				warn "\nInserting new topic\n";
				$topic_handler->insertTopicRow(\%topic_row_ref);

			}
			# Run all of the listeners (2nd pass, inserting takes place)
			$this->runListeners('saveTopic',$topicObject, $cUID,\%th_row_ref);
		}
	# give the th_row_ref back
	return \%th_row_ref;

}

=pod TML

---++ ObjectMethod getVersionInfoTopic($topicObject, $rev, $attachment) -> \%info

Get revision info of a topic or attachment.
   * =$topicObject= Topic object, required
   * =$rev= revision number. If 0, undef, or out-of-range, will get info
     about the most recent revision.
   * =$attachment= (optional) attachment filename; undef for a topic
Return %info with at least:
| date | in epochSec |
| user | user *object* |
| version | the revision number |
| comment | comment in the VC system, may or may not be the same as the comment in embedded meta-data |
=cut

sub getVersionInfoTopic {
	my ($this,$topicObject, $rev) = @_;
	my ($web_name,$topic_name) = ($topicObject->web,$topicObject->topic);
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	my $topic_row;
	if($rev){
		$topic_row = $topic_handler->LoadTHRow($web_name,$topic_name,$rev);
	}
	else{
		$topic_row = $topic_handler->LoadTHRow($web_name,$topic_name);
	}
	my %info;

	$info{date} = $topic_row->{timestamp_epoch};
        $info{author} = $topic_row->{user_key};
	$info{version} = $topic_row->{revision};
	# TODO: add this to the cache
	return \%info;

}

=pod TML

---++ ObjectMethod getNextRevision ( $topicObject  ) -> $revision
   * =$topicObject= - Foswiki::Meta for the topic
Get the ientifier for the next revision of the topic. That is, the identifier
for the revision that we will create when we next save.

=cut

# SMELL: There's an inherent race condition with doing this, but it's always
# been there so I guess we can live with it.
sub getNextRevision{
    my( $this, $topicObject ) = @_;
    die "Fix this";
}

=pod TML

---++ ObjectMethod atomicUnlock( $topicObject )

   * =$topicObject= - Foswiki::Meta topic object
Release the topic lock on the given topic. A topic lock will cause other
processes that also try to claim a lock to block. It is important to
release a topic lock after a guard section is complete. This should
normally be done in a 'finally' block. See man Error for more info.

Topic locks are used to make store operations atomic. They are
_note_ the locks used when a topic is edited; those are Leases
(see =getLease=)

=cut

sub atomicUnlock {
	my ( $this, $topicObject ) = @_;
	# nothing to return b/c Postgresql does the locking for you.
	return undef;
}


=pod TML

---++ ObjectMethod atomicLock( $topicObject, $cUID )

   * =$topicObject= - Foswiki::Meta topic object
   * =$cUID= cUID of user doing the locking
Grab a topic lock on the given topic.

=cut

sub atomicLock {
	my ( $this, $topicObject, $cUID ) = @_;
	# nothing to return b/c Postgresql does the locking for you.
	return undef;
}
=pod TML

---++ ObjectMethod atomicLockInfo( $topicObject ) -> ($cUID, $time)
If there is a lock on the topic, return it.

=cut

sub atomicLockInfo {
	my ( $this, $topicObject ) = @_;
	# nothing to return b/c Postgresql does the locking for you.
	return undef;
}

=pod TML

---++ ObjectMethod getPreference($web,$topic,$key ) -> $value

Get a value for a preference defined *in* the object. 

=cut
sub getPreference {
	my ($this,$web,$topic,$key) = @_;

	my $mphandler = Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::->init($this->{site_handler});

	# Do select transaction to get the value
	return $mphandler->LoadPreference($web,$topic,$key);; 
}
=pod TML

---++ ObjectMethod getCascadeACLs($web, $topic, $mode) -> $value

Get a value for a ACL(mode = VIEW,CHANGE, or RENAME) defined *in* the object, the web, and the site. 

=cut
sub getCascadeACLs {
	my ($this,$web,$topic,$mode) = @_;
	my $mphandler = Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::->init($this->{site_handler});
	return $mphandler->LoadCascadeACLs($web,$topic,$mode);
}
=pod TML

---++ ObjectMethod getFormField($topicObject, $form_name, $field_name) -> $field_value

Returns a hash {'name' => $name, 'value' => $value, 'title' => $name, 'form_key' => $form_key} 

=cut
sub getFormField {
	my ($this,$topicObject, $form_WT, $field_name) = @_;
	# get the topic_history_key from $topicObject
	my ($web,$topic) = ($topicObject->web,$topicObject->topic);
	my $topichandler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	my $th_key = $topichandler->fetchTHRowByWTR($web,$topic);
	# if empty, then load it from the db
	my $cowboy = $topichandler->LoadTHRow($web,$topic);
	$th_key = $topichandler->fetchTHKeyByWTR($web,$topic);
	
	# get the dataform handler
	my $dfhandler = Foswiki::Contrib::DBIStoreContrib::DataformHandler::->init($this->{site_handler});
	
	# if $form_name is null, just try to match the field name
	# TODO: Ignoring the need to get the form_key from $form_name
	# check the local cache first
	my $field_row = $dfhandler->fetchDataFieldRow($th_key,undef,$field_name);
	return $field_row if $field_row;
	
	# fetch from the database
	my $x = $dfhandler->loadDataFieldRow($th_key);
	#require Data::Dumper;
	#my $kaw = Data::Dumper::Dumper($x);
	#die "($web,$topic)($th_key)\n($kaw)";
	# {forms}->{$form_key}->{SalesContacts}->{name=>'SalesContacts',value=>'CompanyName'}
	$field_row = $dfhandler->fetchDataFieldRow($th_key,undef,$field_name);
	return $field_row;
}

=pod TML

---++ ObjectMethod getAvailableForms() -> \@(list of $web.$topic of Form Definition topics)
 

=cut
sub getAvailableForms {
	my ($this) = @_;
	my $dfhandler = Foswiki::Contrib::DBIStoreContrib::DataformHandler::->init($this->{site_handler});
	my @available_forms = @{$dfhandler->getAvailableForms()};
		
	return \@available_forms;
}

=pod TML

---++ ObjectMethod parseFormDefinition($web, $topic) -> \@fields

Gets the JSON definition of the Form from the database and converts it to use for  

=cut

sub parseFormDefinition {
	my ($this,$formObj,$web,$topic) = @_;
	my $dfhandler = Foswiki::Contrib::DBIStoreContrib::DataformHandler::->init($this->{site_handler});

	my $field_ref = $dfhandler->getDataformDefinitionByWT($web,$topic);
	return undef unless scalar(keys %$field_ref) > 0;
	my @officialField;
	foreach my $field_name (keys %$field_ref) {
		my $fieldDef = Foswiki::Form::createField( $formObj,
	      	        $field_ref->{$field_name}->{type},
	                name          => $field_ref->{$field_name}->{name},
	                title         => $field_ref->{$field_name}->{title},
	                size          => $field_ref->{$field_name}->{size},
	                value         => $field_ref->{$field_name}->{value},
	                tooltip       => $field_ref->{$field_name}->{tooltip},
	                attributes    => $field_ref->{$field_name}->{attributes},
	                definingTopic => $dfhandler->fetchTopicKeyByWT($web,$topic),
	                web           => $web,
	                topic         => $topic
		);
		push( @officialField, $fieldDef );
	}
	
	return \@officialField;

}


=pod TML

---++ ObjectMethod putIncludeInCache($web, $topic, $section, $text) -> 


=cut
sub putIncludeInCache {
	my ($this,$web, $topic, $section, $text) = @_;

	my $topichandler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	# get th_key

	my $th_key = $topichandler->fetchTHKeyByWTR($web,$topic);
	unless($th_key){
		$topichandler->LoadTHRow($web,$topic);
		$th_key = $topichandler->fetchTHKeyByWTR($web,$topic);
	}
	$topichandler->putIncludeSectionByTHKey($th_key,$section,$text);

	return $th_key;	
}


=pod TML

---++ ObjectMethod fetchIncludeInCache($web, $topic, $section) -> $text 


=cut
sub fetchIncludeInCache {
	my ($this,$web, $topic, $section) = @_;

	my $topichandler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	# get th_key
	my $th_key = $topichandler->fetchTHKeyByWTR($web,$topic);
	unless($th_key){
		$topichandler->LoadTHRow($web,$topic);
		$th_key = $topichandler->fetchTHKeyByWTR($web,$topic);
	}
	return $topichandler->fetchIncludeSectionByTHKey($th_key,$section);
}

=pod TML

---++ ObjectMethod fetchFromMemcached($cache,$key) -> $value


=cut
sub fetchFromMemcached {
	my ($this, $cache,$key) = @_;

	my $topichandler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	return $topichandler->fetchMemcached($cache,$key);
}

=pod TML

---++ ObjectMethod putInMemcached($cache,$key,$value) -> $value


=cut
sub putInMemcached {
	my ($this,$cache,$key,$value,$seconds) = @_;
	my $topichandler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	return $topichandler->putMemcached($cache,$key,$value,$seconds);
}
########################################################################################
#################################       Webs     #######################################
########################################################################################

sub webExists {
	my $this = shift;
	my $web = shift;
	#print "dbi::webExists()\n";
	my $web_handler = Foswiki::Contrib::DBIStoreContrib::WebHandler::->init($this->{site_handler});
	return undef unless $web_handler->fetchWebRowKeyByW($web);
	return 1;
}


# this is only for subwebs
sub eachWeb {
	my $this = shift;
	my ($web_name, $all ) = @_;
	# returns a undef list	
	my $web_handler = Foswiki::Contrib::DBIStoreContrib::WebHandler::->init($this->{site_handler});
	my $list_ref = $web_handler->LoadListOfWebs($web_name,$all);
	require Foswiki::ListIterator;
	return new Foswiki::ListIterator( $list_ref );
}
########################################################################################
#################################   Attachments    #####################################
########################################################################################
=pod
sub getRevisionHistory_Attachment {
	my $this = shift;
	my ($topicObject,$attachment) = @_;
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	my $maxRev = $this->getLatestRevisionID_Attachment($web_name,$topic_name,$attachment);
	return new Foswiki::Iterator::NumberRangeIterator( $maxRev, 1 );
}
=cut
sub attachmentExists {
	my( $this, $topicObject, $attachment_name ) = @_;
	return 1;	
}
=pod TML

---++ ObjectMethod openAttachment( $topicObject, $attachment_name, $mode, %opts  ) -> $text

Opens a stream onto the attachment. This method is primarily to
support virtual file systems, and as such access controls are *not*
checked, plugin handlers are *not* called, and it does *not* update the
meta-data in the topicObject.

=$mode= can be '&lt;', '&gt;' or '&gt;&gt;' for read, write, and append
respectively. %

=%opts= can take different settings depending on =$mode=.
   * =$mode='&lt;'=
      * =version= - revision of the object to open e.g. =version => 6=
   * =$mode='&gt;'= or ='&gt;&gt;'
      * no options
Errors will be signalled by an =Error= exception.

=cut
sub openAttachment {
	my ( $this, $topicObject, $attachment_name, $mode, %opts ) = @_; #the @opts is really a %opts.  don't worry too much 

	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	return undef unless $web_name && $topic_name && $attachment_name;
	my $version = $opts{version};
	$version = undef unless $version >= 1;

	my $attachment_handler = Foswiki::Contrib::DBIStoreContrib::AttachmentHandler->init($this->{site_handler});
	# try to find it in the cache first and only if Reading the File!
	#warn "OpenAttachment ($attachment_name,$version)\n";
	my $tempFH = $attachment_handler->openStreamByWTAR($web_name,$topic_name,$attachment_name,$version,$mode);
	
	return $tempFH;	

}
=pod
---+ saveAttachment($topicObject, \%opts)
This lo_import the file into Postgres and updates the attachment table
   * =%opts= may include:
      * =name= - Name of the attachment
      * =dontlog= - don't add to statistics
      * =comment= - comment for save
      * =hide= - if the attachment is to be hidden in normal topic view
      * =stream= - Stream of file to upload. Uses =file= if not set.
      * =file= - Name of a *server* file to use for the attachment
        data. This should be passed if it is known, as it may be used
        to optimise handler calls.
      * =filepath= - Optional. Client path to file.
      * =filesize= - Optional. Size of uploaded data.
      * =filedate= - Optional. Date of file.
      * =author= - Optional. cUID of author of change. Defaults to current.
      * =notopicchange= - Optional. if the topic is *not* to be modified.
        This may result in incorrect meta-data stored in the topic, so must
        be used with care. Only has a meaning if the store implementation 
        stores meta-data in topics.
=cut

sub saveAttachment{ 
	my ( $this, $topicObject, $opts ) = @_;

	my $attachment_handler = Foswiki::Contrib::DBIStoreContrib::AttachmentHandler->init($this->{site_handler});


	my $filename = $opts->{name};
	my $comment = $opts->{comment};
	my $stream = $opts->{stream};
	my $size = $opts->{size};
	my $cUID = $opts->{author};
	my ($web_name,$topic_name) = ($topicObject->web,$topicObject->topic);

	my ($fname,$dir_empty01,$ftype) = File::Basename::fileparse($filename,qr/\.[^.]*/);
	$ftype =~ s/^\.//; 
	my $attachment_name = $filename;
	$attachment_handler->database_connection()->{AutoCommit} = 1;
	# First, get the attachment_history row 
	my $ahrow = $attachment_handler->LoadAHRow($web_name,$topic_name,$attachment_name);
	my $attachmentExists = 0;

	my ($topic_key,$attachment_key);
	if(defined($ahrow->{key})){
		# the attachment already exists
		$attachmentExists = 1;
		$topic_key = $ahrow->{topic_key};
		$attachment_key = $ahrow->{attachment_key};
		$ahrow->{version} += 1;
	}

	else{
		# the attachment does not exist
		# get the latest topic row
		my $topic_handler = bless $attachment_handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
		$topic_handler->LoadTHRow($web_name,$topic_name) unless $topic_key;
		$topic_key = $topic_handler->fetchTopicKeyByWT($web_name,$topic_name);
		# kill the process if the Topic does not even exist
		return undef unless $topic_key;
		$attachment_handler = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::AttachmentHandler;
		$ahrow->{topic_key} = $topic_key;
		$ahrow->{version} = 1;
		# create attachment key incase this is a new topic
		$attachment_key = $attachment_handler->createUUID unless $attachment_key;
		$ahrow->{attachment_key} = $attachment_key;
	}

	# fill in the info for ahrow
	$ahrow->{size} = $size;
	$ahrow->{timestamp_epoch} = time();
	$ahrow->{user_key} = $cUID;
	$ahrow->{file_store_key} = '';
	$ahrow->{comment} = $comment || $ahrow->{comment};
	$ahrow->{comment} ||= '  ';
	$ahrow->{comment_key} = '';
	$ahrow->{file_name} = $fname;
	$ahrow->{file_type} = $ftype;

	############# Start the Transaction ##############
	$attachment_handler->database_connection()->{AutoCommit} = 0;
	$attachment_handler->database_connection()->{RaiseError} = 1;

	eval{
		# must defer constraints until after the transaction is finished
		$attachment_handler->set_to_deferred();

		# insert the comment
		$ahrow->{comment_key} = $attachment_handler->insert_Blob_Store($comment);
		# get the file key by doing an lo_import of the file
		$ahrow->{file_store_key} = $attachment_handler->saveStream({stream => $stream, size => $size, web_name => $web_name, 
					topic_name => $topic_name, file_name => $filename, attachment_row => $ahrow});
		#warn "File: ($fname.$ftype)\n";
		my $ahrow_key = $attachment_handler->insertAHRow($ahrow);
		
		
		unless($attachmentExists){
			# topic does not exist, so insert into Attachments
			my %attachmentRow;
			$attachmentRow{key} = $attachment_key;
			$attachmentRow{link_to_latest} = $ahrow_key;
			$attachmentRow{current_attachment_name} = $filename;
			$attachmentRow{current_topic_key} = $topic_key;			
			$attachment_handler->insertAttachmentRow(\%attachmentRow);
		}
		$attachment_handler->database_connection()->commit;
	};
	if ($@) {
		warn "Rollback - failed to save your attachment for reason:\n $@";
		$attachment_handler->database_connection()->errstr;
		eval{
			$attachment_handler->database_connection()->rollback;
		};
	}
	
}

########################################################################################
#################################    Dual Use    #######################################
########################################################################################
sub getRevisionHistory {
	my $this = shift;
	my ($topicObject, $attachment ) = @_;
	# split this function into 2: 1 for Topics, 1 for Attachments
	return $this->getRevisionHistory_Topic($topicObject) unless $attachment;
	return $this->getRevisionHistory_Attachment($topicObject,$attachment) if $attachment;
	return undef;
}

=pod TML

---++ ObjectMethod getVersionInfo($topicObject, $rev, $attachment) -> \%info

Get revision info of a topic or attachment.
   * =$topicObject= Topic object, required
   * =$rev= revision number. If 0, undef, or out-of-range, will get info
     about the most recent revision.
   * =$attachment= (optional) attachment filename; undef for a topic
Return %info with at least:
| date | in epochSec |
| user | user *object* |
| version | the revision number |
| comment | comment in the VC system, may or may not be the same as the comment in embedded meta-data |
=cut

sub getVersionInfo {
	my ($this,$topicObject, $rev, $attachment) = @_;
	#return $this->getVersionInfoAttachment($topicObject, $rev, $attachment) if $attachment;
	return $this->getVersionInfoTopic($topicObject, $rev) unless $attachment;
}
############# ATTACHMENTS ON TOPICS #############

=pod TML

---++ ObjectMethod getAttachmentRevisionInfo($attachment, $rev) -> \%info
   * =$attachment= - attachment name
   * =$rev= - optional integer attachment revision number
Get revision info for an attachment. Only valid on topics.

$info will contain at least: date, author, version, comment

=cut
sub getAttachmentVersionInfo {
    my ( $this,$web_name,$topic_name,$attachment_name, $version ) = @_;
	my $attachment_handler = Foswiki::Contrib::DBIStoreContrib::AttachmentHandler::->init($this->{site_handler});
	my $ahrow = $attachment_handler->LoadAHRow($web_name,$topic_name,$attachment_name,$version);
	return { date=>$ahrow->{timestamp_epoch}, author=>$ahrow->{user_key}, version=>$ahrow->{version}, comment=>$ahrow->{comment}};
}

sub getLease {
	my $this = shift;
	my $topicObject = shift;
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	# TODO: do we need leases for SQL databases?
	return undef;
}


sub setLease {
	my $this = shift;
	my $topicObject = shift;
	#print "dbi::setLease()\n";
	my ($web_name,$topic_name) = ($topicObject->web(),$topicObject->topic());
	# TODO: do we need leases for SQL databases?
}
=pod TML

---++ ObjectMethod query($query, $inputTopicSet, $session, \%options) -> $outputTopicSet

Search for data in the store (not web based).
   * =$query= either a =Foswiki::Search::Node= or a =Foswiki::Query::Node=.
   * =$inputTopicSet= is a reference to an iterator containing a list
     of topic in this web, if set to undef, the search/query algo will
     create a new iterator using eachTopic() 
     and the topic and excludetopics options

Returns a =Foswiki::Search::InfoCache= iterator

This will become a 'query engine' factory that will allow us to plug in
different query 'types' (Sven has code for 'tag' and 'attachment' waiting
for this)

=cut
sub query {
    my ( $this, $query, $inputTopicSet, $session, $options ) = @_;

    my $engine;
    if ( $query->isa('Foswiki::Query::Node') ) {
        unless ( $this->{queryFn} ) {
            eval "require $Foswiki::cfg{Store}{QueryAlgorithm}";
            die
"Bad {Store}{QueryAlgorithm}; suggest you run configure and select a different algorithm\n$@"
              if $@;
            $this->{queryFn} = $Foswiki::cfg{Store}{QueryAlgorithm} . '::query';
        }
        $engine = $this->{queryFn};
    }
    else {
        ASSERT($query->isa('Foswiki::Search::Node')) if DEBUG;
        unless ( $this->{searchQueryFn} ) {
            eval "require $Foswiki::cfg{Store}{SearchAlgorithm}";
            die
"Bad {Store}{SearchAlgorithm}; suggest you run configure and select a different algorithm\n$@"
              if $@;
            $this->{searchQueryFn} =
              $Foswiki::cfg{Store}{SearchAlgorithm} . '::query';
        }
        $engine = $this->{searchQueryFn};
    }

    no strict 'refs';
    return &{$engine}( $query, $inputTopicSet, $session, $options );
    use strict 'refs';
}

sub saveToTar {
	my $this = shift;
	# create a topic handler object
	my $scrap_handler = $this->{site_handler};
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($scrap_handler);
	$topic_handler->saveToTar();	
	
}

1;
__END__
Module of Foswiki Enterprise Collaboration Platform, http://Foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. All Rights Reserved.
Foswiki Contributors are listed in the AUTHORS file in the root of
this distribution. NOTE: Please extend that file, not this notice.

Additional copyrights apply to some of the code in this file, as follows

Copyright (C) 2001-2007 Peter Thoeny, peter@thoeny.org
Copyright (C) 2001-2008 TWiki Contributors. All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
