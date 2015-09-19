# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::LinkHandler;
# Links table -> subset of Topic_History

use strict;
use warnings;


use Assert;

use IO::File   ();
use DBI	       ();
use File::Copy ();
use File::Spec ();
use File::Path ();
use Fcntl    qw( :DEFAULT :flock SEEK_SET );
use DBI				    ();
use DBD::Pg			    ();
use Data::UUID			    ();
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use File::Slurp qw(write_file);
use DBI qw(:sql_types);
use File::Basename				();
use Foswiki::Func ();

use base ("Foswiki::Contrib::DBIStoreContrib::TopicHandler");


# (Handler object) -> LinkHandler Object

sub init {
	# TODO:check that the argument is a handler object First!
	# blah........
	my $class = shift;
	my $this = shift;
	return bless($this,$class);
}



my %SourceToMetaHash = (
'saveTopic' => {  ### - Start ####################################
### @vars=($topicObject, $cUID,\%th_row_ref)
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	# nothing needs to be done because the parent data was already written to the LINK meta data in the $topicObject
	return undef;
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub { 
	return undef; 
},
'FIELD'=> sub { 
	return undef; 
},
'PREFERENCE'=> sub { 
	return undef; 
}
,
'LINKS'=> sub {
	my ($this,$topicObject, $cUID,$th_row_ref) = @_;

	# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	my @ListOfDests = ('link_type','dest_t','dest_th','dest_a','dest_ah','blob_key');
	my @links = $topicObject->find( 'LINK' );

	my %alreadyDone;
	my @linksGuid;
	my @parent_counter;
	foreach my $link (@links){
		# insert the link

		my %link_hash;
		my @alreadyDoneTemp;
		push(@alreadyDoneTemp, $th_row_ref->{key});
		$link_hash{topic_history_key} = $th_row_ref->{key};

		foreach my $destKey (@ListOfDests) {
			$link_hash{$destKey} = $link->{$destKey};
			push(@alreadyDoneTemp,$link_hash{$destKey});
		}
		my ($thlink,$linktype, $dest_t) =($link_hash{topic_history_key},$link_hash{link_type},$link_hash{dest_t});
		push(@linksGuid,$link_hash{link_type}.'@'.$link_hash{dest_t});
		# make sure we are not double counting 
		$this->insert_link(\%link_hash);# unless $alreadyDone{join(',',@alreadyDoneTemp)};
		$alreadyDone{join(',',@alreadyDoneTemp)} = 1;
		if($link_hash{link_type} eq 'PARENT'){
			my $crap = $link_hash{dest_t};
			push(@parent_counter,$crap);
			
		}
	}

	return 1; 
}
},  #### saveTopic - Finished


'convertForSaveTopic'  => {  ### - Start ####################################
### @vars=($topicObject,$cUID,$options)
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	my ($this,$topicObject,$cUID,$options) = @_;

	# clean up the parent link
	my $parent_name = $topicObject->getParent();
	
	# TODO: change WebHome to match the offical webhome in Webs
	$parent_name = 'WebHome' unless $parent_name;
	# (web.topic)-> topic_key);
	my ($web,$topic) = Foswiki::Func::normalizeWebTopicName($topicObject->web, $parent_name);
	
	my $parent_key = $this->fetchTopicKeyByWT($web,$topic);
	
	unless($parent_key){
		$this->LoadTHRow($web,$topic,'');
		$parent_key = $this->fetchTopicKeyByWT($web,$topic);
		return 0 unless $parent_key;
	}

	# replace the TOPICPARENT meta in the $topicObject
	# type -> (LINK, IMAGE, INCLUDE, PARENT)
	# -note- not using putKeyed instead of put b/c we  want to add not replace this row
	my %linkRef;
	$linkRef{link_type} = 'PARENT';
	$linkRef{dest_t} = $parent_key;

	$this->putMetaLink($topicObject,\%linkRef); # $topicObject->put( 'LINK',\%linkRef )
	
	# finished-

	return 1; 
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub { 
	###### This is to make sure that the dataform definition is properly linked  #####
	my ($this,$topicObject,$cUID,$options) = @_;

	## Get FORM (web,topic)
	my $form_ref = $topicObject->get('FORM');
	return undef unless $form_ref; 
	my ($formWeb,$formTopic) = Foswiki::Func::normalizeWebTopicName($topicObject->web,$form_ref->{name});
	
	## Need to get the namekey
	my $th_key = $this->fetchTHKeyByWTR($formWeb,$formTopic);
	unless($th_key){
		# do a SELECT to get the th_key
		my $throwRef = $this->LoadTHRow($formWeb,$formTopic);
		$th_key = $throwRef->{key};
	}
	# put the Form name key
	# type -> (LINK, IMAGE, INCLUDE, PARENT)
	# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	my %linkRef;
	$linkRef{link_type} = 'LINK';
	$linkRef{dest_th} = $th_key;

	$this->putMetaLink($topicObject,\%linkRef); # $topicObject->put( 'LINK',\%linkRef )
	

	return 1; 
},
'FIELD'=> sub { 
	return undef; 
},
'PREFERENCE'=> sub { 
	return undef; 
}
,
'LINKS'=> sub { 
	# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	my ($this,$topicObject,$cUID,$options) = @_;
	my @link_hash;
	my $text = $topicObject->text;
	#### do a search ####
	my @links_match =  ($text =~ m/\[+(\[(\/?[^(\[|\])]+)\])?(\[(\/?[^(\[|\])]+)\])\]/g); # [[web.topic][original text]] -> $2 web.topic $4 original text or $4 web.topic
	
	my $scalarB = scalar(@links_match);
	my $i = 0;
	my @b_return;
	my %lhash;

	while($i < $scalarB){
		my ($linkWT,$origText);

		($linkWT,$origText) = ($links_match[$i+1],$links_match[$i+3]) if $links_match[$i];
		($linkWT,$origText) = ($links_match[$i+3],'') unless $links_match[$i];
		my ($link_web,$link_topic) = Foswiki::Func::normalizeWebTopicName($topicObject->web,$linkWT);

		## Need to get the namekey
		my $throwRef = $this->LoadTHRow($link_web,$link_topic);
		my $link_topic_key = $this->fetchTopicKeyByWT($link_web,$link_topic);
		$lhash{$linkWT} = $link_topic_key;
		
		### replace ###
		if($lhash{$linkWT}){
			bless $this, *Foswiki::Contrib::DBIStoreContrib::LinkHandler;
			$this->putMetaLink($topicObject,{name => join('&',$link_topic_key,'LINK'), dest_t => $link_topic_key, link_type => 'LINK'});
			my $replace_text;
			$replace_text = '[['.$lhash{$linkWT}.']['.$origText.']]' if $origText ;
			$replace_text = '[['.$lhash{$linkWT}.']]' unless $origText;
			#$replace_text = _escapebad($replace_text);
			# (\[\[$linkWT\]\])
			$text =~ s/(\[\[$linkWT\]\[$origText\]\])/$replace_text/g if $origText;
			$text =~ s/(\[\[$linkWT\]\])/$replace_text/g unless $origText;
		}
		
		# increment by 4
		$i += 4;
	
	}
	
	$topicObject->text($text);
	
	return 1;
}
},  #### convertForSaveTopic - Finished


'readTopic'  => {  ### - Start ############   $topicObject,$topic_row  ##################
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 

	return undef; 
},
'TOPICPARENT'=> sub {
	my $this = shift;
	my ($topicObject,$topic_row) = @_;
	my $arrayRef = $this->LoadLHRow($topic_row->{key});
	foreach my $rowref (@$arrayRef) {
		if($rowref->{link_type} eq 'PARENT'){
			
			my $topic_key = $rowref->{dest_t};
			#die "Parent: $topic_key\n";
			my ($web_name,$topic_name) = $this->LoadWTFromTopicKey($topic_key);

			$topicObject->putKeyed( 'TOPICPARENT', { name => "$web_name.$topic_name" } );
			return "$web_name.$topic_name";
		}
	}
	return undef; 
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},

'FORM'=> sub { 
	return undef; 
},
'FIELD'=> sub { 
	return undef; 
},
'PREFERENCE'=> sub { 
	return undef; 
},
'LINKS'=> sub { 
	# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	my $this = shift;
	my ($topicObject,$topic_row) = @_;
	my $text = $topicObject->text;

	### Load the topicObject ###
	my $arrayRef = $this->LoadLHRow($topic_row->{key});
	my @toasty;
	foreach my $link_ref (@$arrayRef){

		$this->putMetaLink($topicObject,$link_ref);
		if($link_ref->{link_type} eq 'LINK'){
			my $dest_t_key = $link_ref->{dest_t};
			my $temp_dest_t_key = quotemeta($dest_t_key);
			
			my @links_match_a =  ($text =~ m/(\[+(\[($temp_dest_t_key)\])?(\[(\/?[^(\[|\]|$temp_dest_t_key)]+)\])\])/g); # [[web.topic][original text]] -> $3 guid $5 original text
			my @links_match_b =  ($text =~ m/(\[+(\[($temp_dest_t_key)\])\])/g); # [[web.topic]] -> $3 guid
			my @links_match = ($text =~ m/(\[\[($temp_dest_t_key)\]\]|\[\[($temp_dest_t_key)\]\[(.*)\]\])/g);
			
			my $scalarA = scalar(@links_match_a);
			my $scalarB = scalar(@links_match_b);
			my $scalarTotal = scalar(@links_match);
			my $i = 0;
			my ($linkWTkey,$origText);
			my $replace_text;
			my $linkWT;
			while( $i < $scalarTotal ){
				my $halfNotFull = 0;
				$halfNotFull = 1 if $links_match[$i+1];
				($linkWTkey,$origText) = ($links_match[$i+2],$links_match[$i+3]) unless $halfNotFull; # [[guid][blah]] -> $3 guid, $4 blah
				($linkWTkey,$origText) = ($links_match[$i+1],'') if $halfNotFull; # [[guid]] -> $2 guid
				
				# (\[\[$linkWT\]\])
				$linkWT = $link_ref->{'dest_t_webname'}.'.'.$link_ref->{'dest_t_topicname'};
				$linkWT = $link_ref->{'dest_t_topicname'} if $link_ref->{'dest_t_webname'} eq $topicObject->web;
				
				$replace_text = '[['.$linkWT.']['.$origText.']]' unless $halfNotFull;
				$replace_text = '[['.$linkWT.']]' if $halfNotFull;
				my $old_text;
				$old_text = "[[$linkWTkey][$origText]]" unless $halfNotFull;
				$old_text = "[[$linkWTkey]]" if $halfNotFull;
				$old_text = quotemeta($old_text);
				
				$text =~ s/($old_text)/$replace_text/g;
				# increment by 4
				$i += 4;
			}
			
		}
		
	}
	
	$topicObject->text($text);
		
	return undef; 
}
},  #### readTopic - Finished
'moveTopic'  => {  ### - Start ########## $throw_key  ##################
'TOPICMOVED' => sub { 
	my ($this,$oldthkey,$newthkey) = @_;
	$this->move_link($oldthkey,$newthkey);
	return undef; 
}
} #### moveTopic - Finished
);

############################################################################################
########################        Listener Call Distributor      #############################
############################################################################################
sub listener {
	my $site_handler = shift;
	my $sourcefunc = shift;
	my @vars = @_;
	# will need this after calling listeners in order to set the site_handler back to what it was before
	my $currentClass = ref($site_handler);
	# need to initialize the object
	my $this = Foswiki::Contrib::DBIStoreContrib::LinkHandler->init($site_handler);

	# these are pieces of the Meta topicObject		
	my @MetaHashObjects = ('TOPICINFO','TOPICMOVED','TOPICPARENT','FILEATTACHMENT','FORM','FIELD','PREFERENCE','CONTENT','LINKS');
	my $sourcFuncRef = $SourceToMetaHash{$sourcefunc};
	foreach my $MetaHash (@MetaHashObjects) {
		$SourceToMetaHash{$sourcefunc}{$MetaHash}->($this,@vars) if exists($SourceToMetaHash{$sourcefunc}{$MetaHash});
	}
	# return handler to previous state
	bless $this, $currentClass;
}
############################   General Purpose Link Move   #################################

# move Link
sub move_link {
	my ($this,$oldthkey,$newthkey) = @_;

	my $Links = $this->getTableName('Links');

	# sha1( 1-source, 2-destination_topic, 3-destination_attachment, 4-destination_topic_history, 5-destination_attachment_history, 6-link_type, 7-blob_key) 
	# foswiki.sha1_uuid(foswiki.text2bytea(?||df1.definition_key)||df1."values")
	my $byteaGen = qq/foswiki.text2bytea(array_to_string(array[?::text,l1.destination_topic::text,l1.destination_attachment::text,l1.destination_topic_history::text,
				l1.destination_attachment_history::text,l1.link_type::text,l1.blob_key::text],'')::text)/; # 1-$newthkey
	my $insertStatement = qq/INSERT INTO $Links ("key", topic_history_key, destination_topic, destination_attachment, 
								destination_topic_history,destination_attachment_history,  link_type, blob_key, original_text)
		SELECT foswiki.sha1_uuid($byteaGen), ?, l1.destination_topic, l1.destination_attachment, l1.destination_topic_history,
				l1.destination_attachment_history, l1.link_type, l1.blob_key, l1.original_text
								FROM $Links l1 WHERE l1.topic_history_key = ?/; # 1-$newthkey, 2-$newthkey, 3-$oldthkey
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->execute($newthkey,$newthkey,$oldthkey);
	# nothing to return
	return 0;

}



############################   General Purpose Link Insert   #################################

# insert Link
sub insert_link {
	my ($this,$link_hash) = @_;

	my $Links = $this->getTableName('Links');
	


	# Link-Key: sha1( 1-source, 2-destination_topic, 3-destination_attachment, 4-destination_topic_history, 5-destination_attachment_history, 6-link_type, 7-blob_key) 
	$link_hash->{'key'} = substr(sha1_hex($link_hash->{'topic_history_key'},$link_hash->{'dest_t'},$link_hash->{'dest_a'},$link_hash->{'dest_th'},$link_hash->{'dest_ah'},$link_hash->{'link_type'},$link_hash->{'blob_key'}),0,-8);
	my $parentname = $link_hash->{'parent_name'};

	# make sure we are not inserting a null row
	die "Null Parent\n" unless( $link_hash->{'dest_t'} || $link_hash->{'dest_a'} || $link_hash->{'dest_th'} || $link_hash->{'dest_ah'});
	#return undef unless( $link_hash->{'dest_t'} || $link_hash->{'dest_a'} || $link_hash->{'dest_th'} || $link_hash->{'dest_ah'});

	# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	my $insertStatement = qq/INSERT INTO $Links ("key", topic_history_key, destination_topic, destination_attachment, destination_topic_history,destination_attachment_history, blob_key, link_type, original_text)
		 SELECT ?,?,?,?,?,?,?,?,?
		 WHERE NOT EXISTS (SELECT 1 FROM $Links l1 WHERE l1."key" = ? );/;
	# this loop is needed b/c Postgres considers '' and undef to be different
	foreach my $undefCol ('dest_t','dest_a','dest_th','dest_ah'){
		delete $link_hash->{$undefCol} unless length($link_hash->{$undefCol}) > 2; # <-- 2 is just a random number, we need to test for UUIDs
	}

	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $link_hash->{'key'});
	$insertHandler->bind_param( 2, $link_hash->{'topic_history_key'});
	$insertHandler->bind_param( 3, $link_hash->{'dest_t'}); # destination_topic
	$insertHandler->bind_param( 4, $link_hash->{'dest_a'}); # destination_attachment
	$insertHandler->bind_param( 5, $link_hash->{'dest_th'}); # destination_topic_history
	$insertHandler->bind_param( 6, $link_hash->{'dest_ah'}); # destination_attachment_history
	$insertHandler->bind_param( 7, $link_hash->{'blob_key'},{ pg_type => DBD::Pg::PG_BYTEA }); # blob_key
	$insertHandler->bind_param( 8, $link_hash->{'link_type'});
	$insertHandler->bind_param( 9, $link_hash->{'original_text'});
	$insertHandler->bind_param( 10, $link_hash->{'key'});

	
	$insertHandler->execute;
	
	return $link_hash->{'key'};

}
# ($th_key)-> enough columns to do Meta Put

sub LoadLHRow {
	my $this = shift;

	my $th_key = shift;
	return undef unless $th_key;
	# may be we already looked it up
	my @arrayReturn;
	return $this->fetchLinks($th_key) if $this->fetchLinks($th_key);
	
	my $Links = $this->getTableName('Links');
	my $Topics = $this->getTableName('Topics');

	my $selectStatement = qq/ SELECT 
  l1."key",
  l1.topic_history_key,
  l1.destination_topic, 
  l1.link_type, 
  l1.destination_topic_history, 
  l1.destination_attachment_history, 
  l1.destination_attachment, 
  dest_t.current_web_key AS dest_t_web, 
  dest_t_tname."value" AS dest_t_topic
FROM 
  foswiki."Links" l1 
	LEFT JOIN (foswiki."Topics" dest_t INNER JOIN foswiki."Blob_Store" dest_t_tname ON dest_t.current_topic_name = dest_t_tname."key")
		ON l1.destination_topic = dest_t."key"
	LEFT JOIN (foswiki."Topic_History" dest_th INNER JOIN foswiki."Blob_Store" dest_th_tname ON dest_th.topic_name = dest_th_tname."key")
		ON l1.destination_topic_history = dest_th."key"
  
WHERE 
  l1.topic_history_key = ? ;/; # 1-th_key

	my $selectHandler = $this->database_connection()->prepare($selectStatement);

	$selectHandler->execute($th_key);

	while(my $rowref = $selectHandler->fetchrow_arrayref){
	
		# 0-lh_key, 1-thkey, 2-destination_topic, 3-link_type, 4-destination_topic_history, 5-destination_attachment_history, 6-destination_attachment,
			#   7-dest_t_web, 8-dest_t_topic
		# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
		my $SinRow = {'link_type'=> $rowref->[3]};

		$SinRow->{'dest_t'} = $rowref->[2];
		$this->LoadWTFromTopicKey($SinRow->{'dest_t'}) if $SinRow->{'dest_t'};
		$SinRow->{'dest_th'} = $rowref->[4];
		$SinRow->{'dest_a'} = $rowref->[5];
		$SinRow->{'dest_ah'} = $rowref->[6];
		$SinRow->{'dest_t_web'} = $rowref->[7];
		$SinRow->{'dest_t_topicname'} = $rowref->[8];
		if($SinRow->{'dest_t'}){
			my $web_name_dest_t = $this->getWebName($SinRow->{'dest_t_web'});
			$SinRow->{'dest_t_webname'} = $web_name_dest_t;
			$this->putTopicKeyByWT($web_name_dest_t,$SinRow->{'dest_t_topicname'},$SinRow->{'dest_t'});
		}
		push(@arrayReturn,$SinRow);

	}
	$this->putLinks($th_key,\@arrayReturn);
	return \@arrayReturn;
}
#### Fetchers ####
# ($th_key)-> \@links
sub fetchLinks {
	my $this = shift;
	my $th_key = shift;
	my $array_of_links = $this->{link_cache}->{$th_key};
	return $array_of_links if $array_of_links;
	
	# if not in local cache, check memcached
	return $this->fetchMemcached('link_cache',$th_key);
}

sub putLinks {
	my $this = shift;
	my $th_key = shift;
	my $array_of_links = shift;
	$this->{link_cache}->{$th_key} = $array_of_links;
	
	# put this in Memcache
	$this->putMemcached('link_cache',$th_key,$array_of_links);
	return 	$array_of_links;
}

# since LINKS are keyed, we need a creative way to make an index
sub putMetaLink {
	my $this = shift;
	my ($topicObject,$linkref) = @_;
	# (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	my @cols10 = ('link_type','dest_t','dest_th','dest_a','dest_ah','blob_key');
	my @nameAssembly;
	foreach my $c1001 (@cols10){
		push(@nameAssembly,$linkref->{$c1001});
	}
	
	# change name if this is a parent link (should only be 1 parent)
	$linkref->{name} = 'PARENT' if $linkref->{link_type} eq 'PARENT';
	# make sure that there is a name for each link
	if(!$linkref->{name} && scalar(@nameAssembly) > 0){
		# this part is to get rid of some annoying warnings, but not errors
		$linkref->{name} = $nameAssembly[0];
		for (my $count33855 = 1; $count33855 < scalar(@nameAssembly); $count33855++) {
			$linkref->{name} .= ','.$nameAssembly[$count33855] if $nameAssembly[$count33855];
		}
	}
	
	#die "Assembly: @nameAssembly" if $linkref->{link_type} eq 'LINK';
	$topicObject->putKeyed( 'LINK',$linkref );
}
# 4 inputs, 1 output
sub _link_subber {
	my $lhash = shift;
	my @ar = @_;
	# $2 web.topic, $4 orig text OR $4 web.topic
	my $return_text;
	return '[['.$lhash->{$ar[3]}.']]' unless $ar[0];
	return '[['.$lhash->{$ar[1]}.']['.$ar[3].']]' if $ar[0];
	
}
# allows us to do search and replace
sub _escapebad {
	my $string = shift;
	my $newstring =~ /\Q$string\E/;
	#bad chars turned good
	return $newstring;
}

1;

__END__
SELECT 
  w1.current_web_name as web,
  tname."value" as topic,
  l1.link_type || '->' ||l1.destination_topic as links
FROM 
foswiki."Topic_History" th1
	INNER JOIN foswiki."Topics" t1 ON t1.link_to_latest = th1."key"
	INNER JOIN foswiki."Blob_Store" tname ON tname."key" = th1.topic_name
	INNER JOIN foswiki."Webs" w1 ON w1."key" = th1.web_key
	INNER JOIN foswiki."Links" l1 ON l1.topic_history_key = th1."key", 
foswiki."Sites" s1
  
WHERE 
s1."key" = w1.site_key AND
s1.current_site_name = 'tokyo.e-flamingo.net' AND
w1.current_web_name = 'Corporate' AND
tname."value" = 'WebHome';

