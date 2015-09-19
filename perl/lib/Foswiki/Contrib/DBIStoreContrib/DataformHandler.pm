# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::DataformHandler;
# Dataform_Data_History table -> subset of Topic_History

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
use Foswiki::Form		();
use JSON  ();


use base ("Foswiki::Contrib::DBIStoreContrib::TopicHandler");

# same arg as Handler->new();
sub new {
	return shift->SUPER::new(@_);
}

# (Handler object) -> TopicHandler Object

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
'EDITTABLE' => sub { 
	return _insertEditTable(@_); 
},
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	return undef;
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub { 
	return undef; 
},
'FIELD'=> sub {
	###### This is for saving Dataforms attached to the topic #######
	## put all the fields into a pretty JSON object
	my ($this,$topicObject, $cUID,$th_row_ref) = @_;
	# with the th_key, let's get all of the field keys?

	my @fields = $topicObject->find( 'FIELD' );
	return undef unless scalar(@fields) > 0;
	
	foreach my $sfield (@fields){
		# insert each field with the topic_history_key
		$sfield->{'topic_history_key'} = $th_row_ref->{key};
		$sfield->{'value'} = " " unless $sfield->{'value'};
		# field_value and value mean the same thing, but field_value is the sql column name, and value is the name used throughout the foswiki code 
		$sfield->{'field_value'} = $sfield->{'value'};
		# the field key is created in the insert_data_field_row function
		$this->insert_data_field_row($sfield);
	}

	return undef; 
},

'PREFERENCE'=> sub {
	#my ($this,$topicObject, $cUID,$th_row_ref) = @_;
	return undef; 
},
'CONTENT'=> sub {
	#### This is for saving Form Definitions #######
	my ($this,$topicObject, $cUID,$th_row_ref) = @_;
	# TODO: get rid of this
	
	my $topic_content = $topicObject->text;
	my $topic_name = $topicObject->topic;
	my $regex_tn = '(FORM|Form)$';
	my @fields = @{Foswiki::Form::_parseFormDefinition($topicObject)};

	return undef unless($topic_name =~ m/$regex_tn/ && scalar(@fields) > 0);
	# Make JSON object
	# clean @fields
	my @clean_array;

	# Modeling: | *Name*  | *Type*  | *Size*  | *Values*  | *Tooltip message*  | *Attributes*  |

	my @listOfKeys = ('name','title','size','value','tooltip','attributes','type');
	my @otherInfoKeys = ('size','value','tooltip','attributes');
	
	foreach my $field01 (@fields) {
		my ($other_info,$def_row);
		foreach my $key02 (@otherInfoKeys) {
			$other_info->{$key02} = $field01->{$key02};
		}
		# load the other_info into json to be put in the blob_store
		my $other_info_blob = JSON::to_json($other_info, {utf8 => 1, pretty => 1});
		$def_row->{'other_info'} = $other_info_blob;
		$def_row->{'topic_history_key'} = $th_row_ref->{key};
		$def_row->{'field_name'} = $field01->{'name'};
		$def_row->{'field_type'} = $field01->{'type'};
		# the 'title' value is the same as the 'name' value, so we shall skip it
		# the field_key or definition_field_key (samething) is calculated upon insertion
		bless $this, *Foswiki::Contrib::DBIStoreContrib::DataformHandler;

		$this->insert_definition_field_row($def_row);
	}

	return 1;
}
}
,  #### saveTopic - Finished


'convertForSaveTopic'  => {  ### - Start ####################################
### @vars=($topicObject,$cUID,$options)
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	return undef; 
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub {
	###### This is to make sure that the dataform definition is properly linked
	my ($this,$topicObject,$cUID,$options) = @_;

	## Get FORM (web,topic)
	my $form_ref = $topicObject->get('FORM');
	return undef unless $form_ref->{name};
	my ($formWeb,$formTopic) = Foswiki::Func::normalizeWebTopicName($topicObject->web,$form_ref->{name});
	## Need to get the namekey
	my $th_key = $this->fetchTHKeyByWTR($formWeb,$formTopic);
	unless($th_key){
		# do a SELECT to get the th_key
		my $throwRef = $this->LoadTHRow($formWeb,$formTopic);
		$th_key = $throwRef->{key};
	}
	
	# put the Form name key
	$topicObject->putKeyed( 'FORM',{ name => $formWeb.'.'.$formTopic, namekey => $th_key } );

	return 1; 
},
'FIELD'=> sub { 
	# we need to get the definition keys for each field
	my ($this,$topicObject,$cUID,$options) = @_;
	# with the th_key, let's get all of the field keys?
	my @fields = $topicObject->find( 'FIELD' );
	return undef unless scalar(@fields) > 0;

	# need to get all of the necessary field keys via form
	my $form_ref = $topicObject->get('FORM');
	# since FORM comes before FIELD, the namekey should already exist
	my $form_key =  $form_ref->{namekey};
	# load all the field keys via the topic_history_key of the definition topic
	my $def_field_hash = $this->fetchDefinitionFieldRow($form_key);
	if(scalar(keys %$def_field_hash) < 1){
		$this->loadDefinitionFieldRow($form_key);
		$def_field_hash = $this->fetchDefinitionFieldRow($form_key);		
	}
	foreach my $sfield (@fields){
		# insert each field with the field key
		$sfield->{'definition_key'} = $def_field_hash->{$sfield->{'name'}}->{'definition_key'};
		# replace the current field with a field that has the definition key
		$topicObject->putKeyed( 'FIELD', $sfield );
	}

	return undef; 
},
'PREFERENCE'=> sub {
	my ($this,$topicObject,$cUID,$options) = @_;
	return undef; 
}
,
'CONTENT'=> sub {
	return undef; 
}
},  #### convertForSaveTopic - Finished


'readTopic'  => {  ### - Start ########## $topicObject,$topic_row  ##################
'TOPICINFO' => sub { 

	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	return undef; 
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
# Load the Form name
'FORM'=> sub { 
	# get the name of the Form Definition Topic
	
	return undef; 
},
# Load the fields
'FIELD'=> sub {
	my ($this,$topicObject,$th_row) = @_;
	my ($topic_key,$th_key) = ($th_row->{topic_key},$th_row->{topic_history_key});
	# with $th_key, get the form rows

	# TODO: fix caching???
	my $field_ref = $this->fetchDataFieldRow($th_key);
	if(scalar(keys %$field_ref) < 1){
		$this->loadDataFieldRow($th_key);
		# {forms}->{$form_key}->{SalesContacts}->{name=>'SalesContacts',value=>'CompanyName'}
		$field_ref = $this->fetchDataFieldRow($th_key);
	}	

	# for each form, get all of the fields
	foreach my $form_key (keys %$field_ref){
		my ($formWeb,$formTopic,$rev) = $this->LoadWTRFromTHKey($form_key);
		#die "Why?($formWeb,$formTopic)($form_key,$topic_key)";
		$topicObject->putKeyed( 'FORM',{ name => $formWeb.'.'.$formTopic, namekey => $form_key } );
		foreach my $field_name (keys %{$field_ref->{$form_key}}){
			$topicObject->putKeyed( 'FIELD', $field_ref->{$form_key}->{$field_name} );
		}
	}

	return 1; 
},
'PREFERENCE'=> sub { 
	return undef; 
}
,
'CONTENT'=> sub {
	return undef; 
}
},  #### readTopic - Finished
'moveTopic'  => {  ### - Start ########## $oldthkey,$newthkey  ##################
'TOPICMOVED' => sub { 
	my ($this,$oldthkey,$newthkey) = @_;
	# dfDefinition
	$this->movedfDefinition($oldthkey,$newthkey);
	# dfData
	$this->movedfData($oldthkey,$newthkey);
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
	my $this = Foswiki::Contrib::DBIStoreContrib::DataformHandler->init($site_handler);
	bless $this, *Foswiki::Contrib::DBIStoreContrib::DataformHandler;

	# these are pieces of the Meta topicObject		
	my @MetaHashObjects = ('TOPICINFO','TOPICMOVED','TOPICPARENT','FILEATTACHMENT','FORM','FIELD','PREFERENCE','CONTENT','LINKS','EDITTABLE');
	my $sourcFuncRef = $SourceToMetaHash{$sourcefunc};
	foreach my $MetaHash (@MetaHashObjects) {
		$SourceToMetaHash{$sourcefunc}{$MetaHash}->($this,@vars) if exists $SourceToMetaHash{$sourcefunc}{$MetaHash} ;
	}
	# return handler to previous state
	bless $this, $currentClass;
}


# ($oldthkey,$newthkey)->$topic_key INSERT for Dataform_Definition_History
# basically, copy the last row
sub movedfDefinition {
	my ($this,$oldthkey,$newthkey) = @_;

	# (key,value)
	my $dfDef = $this->getTableName('Dataform_Definition');
	my $insertStatement = qq/INSERT INTO $dfDef ("key","value")
								SELECT ? , dfdef1."value"
								FROM $dfDef dfdef1 WHERE dfdef1."key" = ?/; # 1-$newthkey, 2-$oldthkey
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->execute($newthkey,$oldthkey);
	return $newthkey;
}

# ($dfdef_row)->$topic_key INSERT for Dataform_Definition_History
sub insertdfDefinition {
	my ($this,$dfdef_row) = @_;

	# (key,value)
	my $dfDef = $this->getTableName('Dataform_Definition');
	my $insertStatement = qq/INSERT INTO $dfDef ("key", "value") VALUES (?,?);/; # 1-key,2-value
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $dfdef_row->{key});
	$insertHandler->bind_param( 2, $dfdef_row->{value}, { pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->execute;

	return $dfdef_row->{key};
}
# ($oldthkey,$newthkey)->undef INSERT for Dataform_Data_History
# basically, copy the last row
sub movedfData {
	my ($this,$oldthkey,$newthkey) = @_;
	# strip hyphens 
	$newthkey =~ s/-//g;
	$oldthkey =~ s/-//g;
	# the key order is
	# $field_data_row->{'field_value'},$field_data_row->{'definition_key'},$field_data_row->{'topic_history_key'}

	my $def_field = $this->getTableName('Definition_Field');
	my $data_field = $this->getTableName('Data_Field');
	my $BS = $this->getTableName('Blob_Store');
	my $byteaGen = qq/ array_to_string(array[df1.field_value::text,df1.definition_field_key::text,?::text],'')::bytea /; # 1-$newthkey
	my $insertStatement = qq/INSERT INTO $data_field (field_key, definition_field_key, field_value, topic_history_key)
		SELECT foswiki.sha1_uuid($byteaGen), df1.definition_field_key, df1.field_value, ? 
								FROM $data_field df1 WHERE df1.topic_history_key = ? /; # 2-$newthkey, 3-$oldthkey
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	#die "($newthkey,$newthkey,$oldthkey)\n";
	#$insertHandler->execute($newthkey,$newthkey,$oldthkey);
	return $newthkey;
}


# dfdata_row insert
sub insertdfData {
	my ($this,$dfdata_row) = @_;

	$dfdata_row->{key} = $this->_createdfDataKey($dfdata_row);
	my $dfData = $this->getTableName('Dataform_Data');
	my $TH = $this->getTableName('Topic_History');
	my $insertStatement = qq/INSERT INTO $dfData ("key", topic_history_key, definition_key, "values")
			 		VALUES (?,?,?,?);/; # 1-key,2-th_key 3-def_key 4-values
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $dfdata_row->{'key'});
	$insertHandler->bind_param( 2, $dfdata_row->{'topic_history_key'});
	$insertHandler->bind_param( 3, $dfdata_row->{'definition_key'});
	$insertHandler->bind_param( 4, $dfdata_row->{'values'}, { pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->execute;

	return $dfdata_row->{key};
}

# 
sub loaddfDataRow {
	my ($this,$th_key) = @_;
	return undef unless $th_key;

	my $dfData = $this->getTableName('Dataform_Data');
	my $BS = $this->getTableName('Blob_Store');
	my $TH = $this->getTableName('Topic_History');
	my $selectStatement = qq/SELECT bdata."value", dfdef.topic_key
FROM 
  $dfData dfdata
	INNER JOIN $BS bdata ON bdata."key" = dfdata."values"
	INNER JOIN $TH dfdef ON dfdef."key" = dfdata.definition_key
WHERE
	dfdata.topic_history_key = ? ;/;

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($th_key);


	# get the data
	my ($dfjson,$def_key);
	$selectHandler->bind_col( 1, \$dfjson );
	$selectHandler->bind_col( 2, \$def_key );
	while ($selectHandler->fetch) {
		my $perlRef = JSON::from_json($dfjson,{utf8 => 1});
		# the three columns are: name title value
		return {topic_key => $def_key,value => $perlRef };
	}

	return undef;
	
}

# gets the Form defintion via ($web,$topic)->$hash_ref of returned JSON
sub getDataformDefinitionByWT {
	my ($this,$web,$topic) = @_;
	require Foswiki::Func;
	my ($formWeb,$formTopic) = Foswiki::Func::normalizeWebTopicName($web,$topic);

	## Need to get the namekey
	my $th_key = $this->fetchTHKeyByWTR($formWeb,$formTopic);
	unless($th_key){
		# do a SELECT to get the th_key
		my $throwRef = $this->LoadTHRow($formWeb,$formTopic);
		$th_key = $throwRef->{key};
	}
	my $def_ref = $this->fetchDefinitionFieldRow($th_key);
	
	if(scalar(keys %$def_ref) < 1){
		$this->loadDefinitionFieldRow($th_key);
		# {form_cache}->{$form_key}->{FieldName}->{name=>'SalesContacts',title=>'SalesContacts',...}
		$def_ref = $this->fetchDefinitionFieldRow($th_key);
	}
    #require Data::Dumper;
    #my $death = Data::Dumper::Dumper($def_ref,$garbage);
	#die "Death:\n$death";
	return $def_ref;
}

# gets all of the available Form Definition $topic_key
sub getAvailableForms {
	my ($this) = @_;

	my $site_key = $this->{site_key};
	my $def_field = $this->getTableName('Definition_Field');
	my $BS = $this->getTableName('Blob_Store');
	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	
	my $selectStatement = qq/SELECT 
  DISTINCT t1."key", w1.current_web_name, tname."value"
FROM 
  $Topics t1
	INNER JOIN $def_field def ON def.topic_history_key = t1.link_to_latest
	INNER JOIN $Webs w1 ON w1."key" = t1.current_web_key
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
WHERE 
  w1.site_key = '$site_key' 
ORDER BY
  w1.current_web_name ASC, tname."value" ASC;
	/; # - no inputs

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute();
	my @return_array;
	my ($formtopickey,$formweb,$formtopic);
	$selectHandler->bind_col( 1, \$formtopickey );
	$selectHandler->bind_col( 2, \$formweb );
	$selectHandler->bind_col( 3, \$formtopic );
	
	while ($selectHandler->fetch) {
		push(@return_array,$formtopickey);
		$this->putTopicKeyByWT($formweb,$formtopic,$formtopickey);
	}
	return \@return_array;
}

# ($th_key,$form_key,'FieldName')->{'name' => $name, 'value' => $value, 'title' => $name}
# if there is no field_name, then all rows are returned
sub fetchDataFieldRow {
	my ($this,$th_key,$form_key,$field_name) = @_;
	my $z;
	if($field_name && $th_key && $form_key){
		
		my $x = $this->{topic_cache}->{$th_key}->{forms}->{$form_key}->{$field_name}; 
		return $x if $x;
		$x = $this->fetchMemcached('topic_cache',$th_key.'forms');
		# $x is in the form of {$def_key1 => $dataForm1, $def_key2 => $dataForm2,..}
		$z = $x->{$form_key}->{$field_name};		
	}
	elsif($field_name && $th_key && !$form_key){
		# maybe no $form_key is provided
		my $x;
		foreach my $f101 (keys %{$this->{topic_cache}->{$th_key}->{forms}}){
			$x = $this->{topic_cache}->{$th_key}->{forms}->{$f101}->{$field_name};
		} 
		return $x if $x;
		$x = $this->fetchMemcached('topic_cache',$th_key.'forms');
		# $x is in the form of {$def_key1 => $dataForm1, $def_key2 => $dataForm2,..}
		foreach my $f101 (keys %$x){
			$z = $x->{$f101}->{$field_name} if $x->{$f101}->{$field_name};
			last
		} 
		#return undef;		
	}
	elsif($form_key && $th_key && !$field_name){
		my $x = $this->{topic_cache}->{$th_key}->{forms}->{$form_key};
		return $x if $x;
		$x = $this->fetchMemcached('topic_cache',$th_key.'forms');
		$z = $x->{$form_key};
	}
	elsif($th_key){
		my $x = $this->{topic_cache}->{$th_key}->{forms};
		return $x if $x;
		$x = $this->fetchMemcached('topic_cache',$th_key.'forms');
		$z = $x;
	}
	else{
		$z = undef;
	}
	return $z;
}

# this function is inefficient, makes many calls to memcached
sub putDataFieldRow {
	my ($this,$th_key,$form_key,$row_ref) = @_;
	return undef unless $row_ref->{'name'} && $form_key && $th_key;
		
	$this->{topic_cache}->{$th_key}->{forms}->{$form_key}->{$row_ref->{'name'}} = $row_ref;
	
	# stuff it in memcache, but we need to stuff the whole thing
	# find out if a full dataform object is already in the cache, which contains all forms attached to a topic
	my $dataforms = $this->fetchDataFieldRow($th_key);
	# add the new data field row
	$dataforms->{$form_key}->{$row_ref->{'name'}} = $row_ref;
	$this->putMemcached('topic_cache',$th_key.'forms',$dataforms);
	return $row_ref;
}


#" {'name','title','topic_history_key','field_key'}" -> insert into the database
sub insert_data_field_row {
	my ($this,$field_row) = @_;
	return undef unless $field_row;

	my $def_field = $this->getTableName('Definition_Field');
	my $data_field = $this->getTableName('Data_Field');
	my $BS = $this->getTableName('Blob_Store');
	
	# need to insert the value into the Blob Store
	my $value_key = $this->insert_Blob_Store($field_row->{'field_value'});
	$field_row->{'field_value'} = $value_key;
	$field_row->{'field_key'} = $this->_createDataFieldkey($field_row);
	my $insertStatement = qq/INSERT INTO $data_field (field_key, definition_field_key, field_value, topic_history_key)
		 VALUES (?,?,?,?);/;# 1-field_key,2-field_key,3-field_value,4-topic_history_key
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $field_row->{'field_key'} ); 
	$insertHandler->bind_param( 2, $field_row->{'definition_key'}); 
	$insertHandler->bind_param( 3, $field_row->{'field_value'},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 4, $field_row->{'topic_history_key'});
	$insertHandler->execute;
	return {$field_row->{'field_key'},$field_row->{'definition_key'},$field_row->{'field_value'},$field_row->{'topic_history_key'}};

}
# used to fetch the form data for an individual topic
# ($th_key)->\@array_of_(name,title,value,form_key)
sub loadDataFieldRow {
	my ($this,$th_key) = @_;
	return undef unless $th_key;
	# check cache
	my $fetchrow = $this->fetchDataFieldRow($th_key);
	return $fetchrow if scalar(keys %{$fetchrow}) > 0;
	
	my $def_field = $this->getTableName('Definition_Field');
	my $data_field = $this->getTableName('Data_Field');
	my $BS = $this->getTableName('Blob_Store');
	
	my $selectStatement = qq/SELECT 
  def_name."value" AS "name", 
  value_blob."value" AS "value",
  def_field.topic_history_key AS "form_key"
FROM 
  $def_field def_field
	INNER JOIN $BS def_name ON def_field.field_name = def_name."key"
	INNER JOIN $BS other_blob ON other_blob."key" = def_field.other_info
	INNER JOIN $data_field data_field ON def_field.field_key = data_field.definition_field_key,
  $BS value_blob
  
	
WHERE 
   value_blob."key" = data_field.field_value and
   data_field.topic_history_key = ? ;/;# 1-th_key
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($th_key);
	my ($name, $value, $form_key);
	$selectHandler->bind_col( 1, \$name );
	$selectHandler->bind_col( 2, \$value );
	$selectHandler->bind_col( 3, \$form_key );
	my @return_array;
	# fetch all of the fields (some of which might be missing if they were left blank)
	while ($selectHandler->fetch) {
#die "howdy:($th_key,$form_key,$name)";
		$this->putDataFieldRow($th_key,$form_key,{'name' => $name, 'value' => $value, 'title' => $name, 'form_key' => $form_key});
		push(@return_array,{'name' => $name, 'value' => $value, 'title' => $name, 'form_key' => $form_key});
	}
	return \@return_array;

}

# this loads all of the field rows into the handler form_cache
sub loadDefinitionFieldRow {
	my ($this,$form_th_key) = @_;

	return undef unless $form_th_key;
	my $def_field = $this->getTableName('Definition_Field');
	my $data_field = $this->getTableName('Data_Field');
	my $BS = $this->getTableName('Blob_Store');
	my $selectStatement = qq/SELECT 
  def_field.field_key, 
  fname."value",
  oinfo."value",
  def_field.field_type
FROM 
  $def_field def_field
	INNER JOIN $BS fname ON fname."key" = def_field.field_name
	INNER JOIN $BS oinfo ON oinfo."key" = def_field.other_info
WHERE 
  def_field.topic_history_key = ?;/; # 1-form_th_key

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($form_th_key);
	my ($name, $field_key,$field_type,$other_info);
	$selectHandler->bind_col( 1, \$field_key );
	$selectHandler->bind_col( 2, \$name );
	$selectHandler->bind_col( 3, \$other_info );
	$selectHandler->bind_col( 4, \$field_type );
	my $return_hash;
	# fetch all of the fields (some of which might be missing if they were left blank)
	my %all_fields;
	while ($selectHandler->fetch) {
		# need to get other definition info
		$return_hash->{'field_name'} = {'field_name' => $name, 'field_key' => $field_key, 'topic_history_key' => $form_th_key,
			 'other_info' => $other_info, 'field_type' => $field_type};
		my $other_info_hash = JSON::from_json($other_info,{utf8 => 1});
		$return_hash->{'field_name'}->{'size'} = $other_info_hash->{'size'};
		$return_hash->{'field_name'}->{'value'} = $other_info_hash->{'value'};
		$return_hash->{'field_name'}->{'tooltip'} = $other_info_hash->{'tooltip'};
		$return_hash->{'field_name'}->{'attributes'} = $other_info_hash->{'attributes'};
		$return_hash->{'field_name'}->{'type'} = $field_type;
		$return_hash->{'field_name'}->{'name'} = $name;
		$return_hash->{'field_name'}->{'title'} = $name;
		# we did the following to clarify the difference between defintion table and the data table
		$return_hash->{'field_name'}->{'definition_field_key'} = $return_hash->{'field_name'}->{'field_key'};
		$return_hash->{'field_name'}->{'definition_key'} = $return_hash->{'field_name'}->{'field_key'};
		my @listOfKeys = ('name','title','size','value','tooltip','attributes','type');
		# don't want to break anything, so this function is only for local cache, not memcache
		$this->putDefinitionFieldRow($form_th_key, $return_hash->{'field_name'});
		$all_fields{$name} = $return_hash->{'field_name'};
	}
	# we have a weird situation, the following function is only for memcache
	$this->putDefinitionAllFields($form_th_key,\%all_fields);
	return $return_hash;
}

# only for memcached 
sub putDefinitionAllFields {
	my ($this,$form_key,$all_fields) = @_;
	#$this->{form_cache}->{$form_key} = $all_fields;
	$this->putMemcached('form_cache',$form_key,$all_fields);
	return $all_fields;
}
# only for local cache
sub putDefinitionFieldRow {
	my ($this,$form_key,$field_row_ref) = @_;
	$this->{form_cache}->{$form_key}->{$field_row_ref->{'field_name'}} = $field_row_ref;
	return $this->{form_cache}->{$form_key}->{$field_row_ref->{'field_name'}};
}

# ($form_th_key,'FieldName') , the field_name is optional
sub fetchDefinitionFieldRow {
	my ($this,$form_key,$field_name) = @_;
	
	my ($form_hash,$field_row);
	$field_row = $this->{form_cache}->{$form_key}->{$field_name} if $field_name;
	$form_hash = $this->{form_cache}->{$form_key} unless $field_name;
	
	$form_hash = $this->fetchMemcached('form_cache',$form_key) unless $field_row || $form_hash;
	
	if($form_key && $field_name){
		# return data for only one field
		return $field_row if $field_row;
		
		# if not, then must be in memcache
		$this->{form_cache}->{$form_key} = $form_hash;
		return $form_hash->{$field_name};
	}
	elsif($form_key){
		$this->{form_cache}->{$form_key} = $form_hash;
		return $form_hash;
	}
	else{
		# nothing to return
		return undef; 
	}
}

sub insert_definition_field_row {
	my ($this,$def_row) = @_;

	$def_row->{'other_info'} = $this->insert_Blob_Store($def_row->{'other_info'});
	$def_row->{'field_name'} = $this->insert_Blob_Store($def_row->{'field_name'});
	$def_row->{'field_key'} = $this->_createDefinitionFieldKey($def_row);
	my $def_field = $this->getTableName('Definition_Field');
	my $data_field = $this->getTableName('Data_Field');
	my $BS = $this->getTableName('Blob_Store');
	my $insertStatement = qq/INSERT INTO $def_field (field_key, topic_history_key, field_name, field_type, other_info)
		 VALUES (?,?,?,?,?);/;
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $def_row->{'field_key'} ); 
	$insertHandler->bind_param( 2, $def_row->{'topic_history_key'}); 
	$insertHandler->bind_param( 3, $def_row->{'field_name'},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 4, $def_row->{'field_type'});
	$insertHandler->bind_param( 5, $def_row->{'other_info'},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->execute;	

}


# key = sha1( 1-topic_history_key, 2-definition_key, 3-values) 
sub _createdfDataKey {
	my ($this,$dfdata_row) = @_;
	return substr(sha1_hex($dfdata_row->{'topic_history_key'},$dfdata_row->{'definition_key'},$dfdata_row->{'values'}),0,-8);
}

sub _createDataFieldkey {
	my ($this,$field_data_row) = @_;
	return substr(sha1_hex($field_data_row->{'field_value'},$field_data_row->{'definition_key'},$field_data_row->{'topic_history_key'}),0,-8);	
}

sub _createDefinitionFieldKey {
	my ($this,$field_def_row) = @_;
	return substr(sha1_hex($field_def_row->{'topic_history_key'},$field_def_row->{'other_info'},$field_def_row->{'field_name'},$field_def_row->{'field_type'}),0,-8);	
}


#################### EDIT TABLES #########################
# key = sha1( 1-topic_history_key, 2-definition_key, 3-values) 

sub _createEditTableDataKey {
	my ($this,$data_row) = @_;

	$data_row->{'key'} = substr(sha1_hex($data_row->{'row_blob'},$data_row->{'row_number'},$data_row->{'topic_history_key'},$data_row->{'definition_key'}),0,-8);
	return $data_row->{'key'};
}

sub _insertEditTable {
	my ($this,$topicObject, $cUID,$th_row_ref) = @_;
	my $th_key = $th_row_ref->{'key'};
	# $topicObject->putKeyed( 'EDITTABLE',{ 'name' => $table_count, 'data' => \@table_rows, 'definition' => $def_hash, 'definition_key' => $def_key } );	
	my @tables = $topicObject->find('EDITTABLE');
	my $row_num = 0;
	foreach my $table (@tables){
		# get the Table definition first!
		#my $crap = $table->{'definition'};
		#die "Crap: ($crap)";
		my $table_def_key = $this->insert_Blob_Store( JSON::to_json($table->{'definition'}, {utf8 => 1, pretty => 1}));
		
		# given the table definition, insert all of the rows!
		my @rows = @{ $table->{'data'} };
		foreach my $row (@rows){
			my $data_row;
			
			$data_row->{'row_blob'} = JSON::to_json($row, {utf8 => 1, pretty => 1});
			$data_row->{'row_blob_key'} = $this->insert_Blob_Store($data_row->{'row_blob'});
			$data_row->{'topic_history_key'} = $th_key;
			$data_row->{'definition_key'} = $table_def_key;
			$data_row->{'row_number'} = $row_num;
			my $data_row_key = $this->insertEditTableRow($data_row);
			
			delete $row->{'_row'};
			$row_num += 1;	
		}
	}
	
	return undef;
}


# table_row insert
sub insertEditTableRow {
	my ($this,$data_row) = @_;
	$data_row->{key} = $this->_createEditTableDataKey($data_row);
	my $ETR = $this->getTableName('EditTableRows');
	my $insertStatement = qq/INSERT INTO $ETR ("key", row_blob, topic_history_key, definition_key, row_number)
			 		VALUES (?,?,?,?,?);/; # 1-"key", 2-row_blob, 3-topic_history_key, 4-definition_key, 5-row_number
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $data_row->{'key'});
	$insertHandler->bind_param( 2, $data_row->{'row_blob_key'},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 3, $data_row->{'topic_history_key'});
	$insertHandler->bind_param( 4, $data_row->{'definition_key'}, { pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 5, $data_row->{'row_number'});
	$insertHandler->execute;

	return $data_row->{key};
}
# topic_key -> json_text
sub getEditTableDefinitionFromInclude {
	my ($this,$topic_key) = @_;
	
	my $ETR = $this->getTableName('EditTableRows');
	my $Topics = $this->getTableName('Topics');
	my $BS = $this->getTableName('Blob_Store');
	my $selectStatement = qq/SELECT 
  def_blob."value"
FROM 
  $ETR etd
	INNER JOIN $BS def_blob ON etd.definition_key = def_blob."key"
	INNER JOIN $Topics t1 ON etd.topic_history_key = t1.link_to_latest
WHERE 
  t1."key" = ?
LIMIT 1;/;# 1-topic_key
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($topic_key);
	my ($dfjson);
	$selectHandler->bind_col( 1, \$dfjson );
	while ($selectHandler->fetch) {
		return $dfjson;
	}
	return undef;
}

# ($handler,$tobj)
sub loadFormOnly {
	my ($this,$topicObject) = @_;
	my $th_row = $this->LoadTHRow($topicObject->web,$topicObject->topic);
	my ($topic_key,$th_key) = ($th_row->{topic_key},$th_row->{topic_history_key});

	# get the json data
	my $row_ref = $this->loaddfDataRow($th_key);
	my $form_key = $row_ref->{topic_key};
	
	return undef unless $form_key;
	# load the Form Name
	my ($formWeb,$formTopic) = $this->LoadWTFromTopicKey($form_key);
	$topicObject->putKeyed( 'FORM',{ name => $formWeb.'.'.$formTopic, namekey => $form_key } );
	my @fields = @{$row_ref->{value}};
	# put the Field data into the $topicObject
	foreach my $field (@fields) {
		$topicObject->putKeyed( 'FIELD', $field );
	}
	return 1; 
}



1;
__END__

search and replace before parsing
('[^'~=]+'|[^'~=\s]+)/('[^'~=\s]+'|[^'~=\s]+)(\s*[~=]\s*)('[^'~=\s]+')


