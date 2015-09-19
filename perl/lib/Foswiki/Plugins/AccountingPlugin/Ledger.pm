package Foswiki::Plugins::AccountingPlugin::Ledger;

use strict;
use Foswiki::Plugins::AccountingPlugin::Splits();
use Foswiki::Plugins::AccountingPlugin::Transactions();
use Foswiki::Func();
use Foswiki::UI::Accounting();

my $keyhash = {
	'site_key' => {},
	'topics' => {},
	'webs' => {},
};
# ($web,$topic)-> $topic_key
sub _add_topic_key {
	return "die";	
}
# enter new transaction into the ledger
sub create_tx {
	my $session = shift;

	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};
	my $current_time = time();
	my $uri_string = $request->queryString();

	# get the web,topic pair (in the future, perhaps we can skip this step)
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	my @accounts_match =  ($uri_string =~ m/split_account=([^;\&]+)/g);
	my @amounts_match = ($uri_string =~ m/split_amount=([^;\&]+)/g);
	my @dc_match = ($uri_string =~ m/split_dc=([^;\&]+)/g);

	if(scalar(@accounts_match) != scalar(@amounts_match) || scalar(@amounts_match) != scalar(@dc_match) || scalar(@dc_match) != scalar(@accounts_match)) {
		die "splits don't match";
	}

	my $N = scalar(@amounts_match);
	my @tx_hash;
	my ($i,$balance) = (0,0);
	my $tx01 = Foswiki::Plugins::AccountingPlugin::Transactions->new();
	
	foreach my $acc01 (@accounts_match) {
		my $split01 = Foswiki::Plugins::AccountingPlugin::Splits->new();
		# make sure to input the account topic key, not the web,topic pair
		$split01->account($topic_handler->_convert_WT_Topics_in($acc01));
		# add to balance
		$split01->amount(abs($amounts_match[$i])*-1) if $dc_match[$i] eq 'd';
		$split01->amount(abs($amounts_match[$i])) if $dc_match[$i] eq 'c';
		$balance += $split01->amount;
		$tx01->add_split($split01);
		$i += 1;
	}
	# check the balance constraint
	if($tx01->balance != 0){
		die "Transaction is unbalanced.  Take a second look.\n";
	}
	# post_date
	# no longer need this!!!
	my $post_date_raw = $request->param('PostDate');
	
	$tx01->post_date_convert($post_date_raw);
	# enter_date
	$tx01->enter_date(time());
	# user_key
	$tx01->user($user_key);
	#require Data::Dumper;
	#my $xo = Data::Dumper::Dumper($tx01);
	#my $yo = Data::Dumper::Dumper($request);
	#die "($post_date_raw)(".$tx01->post_date().")\n\n$xo\n\n$yo";	
	# generate tx key
	$tx01->generate_key();
	
	########## Start building the transaction topic ############
	# find the template topic
	my $accTemplate_key = Foswiki::Func::getPreferencesValue('TRANSACTIONTEMPLATE',$web);

	my ($temp_web,$temp_topic) = @{$topic_handler->_convert_WT_Topics_out($accTemplate_key)};
	#die "Template Key: (($temp_web,$temp_topic),$accTemplate_key)";
	# load the topic
	my ($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
	# change the topic name
	$temp_meta->topic($tx01->key);
	# add the parent topic
	$temp_meta->put( 'TOPICPARENT', { name => $request->param('topicparent')} );
	# add the form fields
	# ('name','title','value') names => PostDate Tags Name
	my ($field1,$field2,$field3);
	($field1->{'name'},$field2->{'name'},$field3->{'name'}) = ("PostDate","Tags","Name");
	($field1->{'title'},$field2->{'title'},$field3->{'title'}) = ("PostDate","Tags","Name");
	($field1->{'value'},$field2->{'value'},$field3->{'value'}) = ($request->param('PostDate'),$request->param('Tags'),$request->param('Name'));
	$temp_meta->remove('FORM');
	$temp_meta->putKeyed( 'FORM', {'name' => 'AccountingJapan.TransactionForm', 'namekey' => $topic_handler->_convert_WT_Topics_in('AccountingJapan.TransactionForm')});
	$temp_meta->putKeyed( 'FIELD', $field1 ) if $field1->{'value'};
	$temp_meta->putKeyed( 'FIELD', $field2 ) if $field2->{'value'};
	$temp_meta->putKeyed( 'FIELD', $field3 ) if $field3->{'value'};
#	require Data::Dumper;
#	my $xo = Data::Dumper::Dumper($temp_meta);
#	die "$xo";
	#require Data::Dumper;
	#die "For Real:($temp_web,$temp_topic)\n\n".Data::Dumper::Dumper($temp_meta);
	# Don't add the SPLIT link (can't add b/c we don't have a topic_history_key yet) AND there is a database trigger
	#$temp_meta->putKeyed( 'LINK',  { name => 'MaxAge', link_type => 'SPLIT', dest_t =>'103' } );
	my %opts01;
	$opts01{'nocommit'} = 1;
	$opts01{'preseed_topic_key'} = $tx01->key;
	my ($w01,$t01) = ($temp_meta->web,$temp_meta->topic);
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;

	# evaluate
	eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();
			
		# save the topic, but don't commit yet
		# even thought it is not commited, we can still find the topic_key and topic_history_key
		$temp_meta->save(%opts01);

		#Foswiki::Func::saveTopic( $temp_meta->web, $temp_meta->topic, $temp_meta, $temp_meta->text, \%opts01 );
		
		# save the transaction, use the transaction handler as the db handler
		$tx01->handler($topic_handler);
		my $success = $tx01->save;

		# commit the transaction
		$topic_handler->database_connection()->commit;
	};
	my $potentialError = $@;
	if ($potentialError) {
		#die "Rollback - failed to save ($w01,$t01) for reason:\n ";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
		die "$potentialError";
		catch Error::Simple with {
            throw Foswiki::OopsException(
                'attention',
                def    => 'save_error',
                web    => $w01,
                topic  => $t01,
                params => [ $@ ]
            );
        };
	}
	
	# redirect to the new page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $temp_meta->web, $temp_meta->topic ) );
	$session->redirect($redirecturl);
	return;
}


# Do markup for Balance
# http://tokyo.e-flamingo.net/bin/view/Operations/OctopsSubSystemAccountingInterface
# %BALANCE{topic="%TOPIC%" level="0" start="2010-4-2" finish="%TODAY%" datefield="PostDate"}%
sub balance_tag_renderer {
	my ($inWeb,$inTopic, $args) = @_;
	
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	
	# get the account key
	require Foswiki::Func;
	my $account_wt = Foswiki::Func::extractNameValuePair( $args );
	$account_wt = Foswiki::Func::extractNameValuePair( $args, 'topic' ) unless $account_wt;
	my $account_key = $topic_handler->_convert_WT_Topics_in($account_wt);
	
	# have to convert dates to epoch time
	require Foswiki::Time;
	my $start_date = Foswiki::Func::extractNameValuePair( $args, 'startdate' );
	$start_date = Foswiki::Time::parseTime($start_date,1) if $start_date;
	$start_date = 1 unless $start_date;
	my $end_date = Foswiki::Func::extractNameValuePair( $args, 'enddate' );
	$end_date = Foswiki::Time::parseTime($end_date,1) if $end_date;
	$end_date = time() unless $end_date;
	
	my $field_name = Foswiki::Func::extractNameValuePair( $args, 'postfield' );
	if(!$start_date || !$end_date || !$field_name){
		return "Insufficient parameters";
	}

	# find out how many levels to go
	my $level = Foswiki::Func::extractNameValuePair( $args, 'level' );
	 
	# here is the massive recursive sql statement needed to get this balance for all
	
	my $Splits = Foswiki::UI::Accounting::getTable('Splits');
	my $Topics = Foswiki::UI::Accounting::getTable('Topics');
	my $Links = Foswiki::UI::Accounting::getTable('Links');
	my $BS = Foswiki::UI::Accounting::getTable('Blob_Store');
	my $Webs = Foswiki::UI::Accounting::getTable('Webs');
	my $dfData = Foswiki::UI::Accounting::getTable('Data_Field');
	my $dfDef = Foswiki::UI::Accounting::getTable('Definition_Field');
	
	# make sure that t_x in the Trash Web are not counted
	my $trash_web = $Foswiki::cfg{TrashWebNameKey};
	
	# ($account_key) -> balance of all payments
	# select statement for level 0
	my $select_statement_l0 = qq/SELECT 
  SUM(sp1.amount)
FROM 
 $Splits sp1
    INNER JOIN 
   (
     $Topics tdf
	INNER JOIN ($dfData dfdata INNER JOIN $BS fvalue ON dfdata.field_value = fvalue."key"
							INNER JOIN $dfDef dfdef ON dfdef.field_key = dfdata.definition_field_key
		) ON  dfdata.topic_history_key = tdf.link_to_latest 
    ) ON tdf."key" = sp1.transaction_key	  
WHERE
 tdf.current_web_key != '$trash_web' AND
 sp1.accounts_key = ? AND fvalue.number_vector >= ? AND fvalue.number_vector <= ? AND dfdef.field_name = foswiki.sha1bytea(?)  
GROUP BY
  sp1.accounts_key/; # 1-account_topic_key, 2-start_date, 3-end_date, 4-field_name
  	# select statement for ALL
	my $select_statement_all = qq/WITH RECURSIVE parent_topic(web_name, topic_name, topic_key, parent_key, dummy) AS (

SELECT 
  w1.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t1."key" AS topic_key,
  l1.destination_topic AS parent_key,
  1 as dummy
FROM 
  $Topics t1
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
	INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
	INNER JOIN $Links l1 ON t1.link_to_latest = l1.topic_history_key AND l1.link_type = 'PARENT'
WHERE 
  t1."key" = ? 

UNION

SELECT 
  w2.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t2."key" AS topic_key,
  l2.destination_topic AS parent_key,
  1 as dummy
FROM 
  $Topics t2
	INNER JOIN $BS tname ON t2.current_topic_name = tname."key"
	INNER JOIN $Webs w2 ON t2.current_web_key = w2."key"
	INNER JOIN $Links l2 ON t2.link_to_latest = l2.topic_history_key AND l2.link_type = 'PARENT' ,
	parent_topic
WHERE
   parent_topic.topic_key = l2.destination_topic 
  
)

SELECT 
  SUM(sp1.amount)
FROM 
 $Splits sp1
    INNER JOIN parent_topic ON sp1.accounts_key = parent_topic.topic_key
    INNER JOIN 
   (
     $Topics tdf
	INNER JOIN ($dfData dfdata INNER JOIN $BS fvalue ON dfdata.field_value = fvalue."key"
							INNER JOIN $dfDef dfdef ON dfdef.field_key = dfdata.definition_field_key
		) ON  dfdata.topic_history_key = tdf.link_to_latest 
    ) ON tdf."key" = sp1.transaction_key	  
WHERE
 fvalue.number_vector >= ? AND fvalue.number_vector <= ? AND dfdef.field_name = foswiki.sha1bytea(?) AND tdf.current_web_key != '$trash_web'
 ;/;# 1-account_topic_key, 2-start_date, 3-end_date, 4-field_name
	
	# ($account_key, $level)->balance
	my $select_statement_lN = qq/WITH RECURSIVE parent_topic(web_name, topic_name, topic_key, parent_key, link_to_latest, dummy, levels) AS (

SELECT 
  w1.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t1."key" AS topic_key,
  l1.destination_topic AS parent_key,
  t1.link_to_latest AS link_to_latest,
  1 as dummy,
  0 as levels
FROM 
  $Topics t1
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
	INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
	INNER JOIN $Links l1 ON t1.link_to_latest = l1.topic_history_key AND l1.link_type = 'PARENT'
WHERE 
  t1."key" = ?

UNION

SELECT 
  w2.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t2."key" AS topic_key,
  l2.destination_topic AS parent_key,
  t2.link_to_latest AS link_to_latest,
  1 as dummy, 
  1 + parent_topic.levels
FROM 
  $Topics t2
	INNER JOIN $BS tname ON t2.current_topic_name = tname."key"
	INNER JOIN $Webs w2 ON t2.current_web_key = w2."key"
	INNER JOIN $Links l2 ON t2.link_to_latest = l2.topic_history_key AND l2.link_type = 'PARENT',
  parent_topic
WHERE
  parent_topic.topic_key = l2.destination_topic AND
  parent_topic.levels < ? + 1

)
SELECT 
	sp1.amount
FROM 
    $Splits sp1
		INNER JOIN parent_topic ON parent_topic.topic_key = sp1.accounts_key 
		INNER JOIN ($dfData dfdata 
				INNER JOIN $BS fvalue ON dfdata.field_value = fvalue."key" 
				INNER JOIN ($dfDef dfdef INNER JOIN $BS fname ON dfdef.field_name = fname."key") 
					ON dfdef.field_key = dfdata.definition_field_key
				INNER JOIN $Topics tdf ON dfdata.topic_history_key = tdf.link_to_latest	
			) ON sp1.transaction_key = tdf."key"

WHERE
	fvalue.number_vector >= ? AND fvalue.number_vector <= ? AND fname."value" = ?
GROUP BY
	parent_topic.dummy;
	/;# 1-account_topic_key, 2-parent level, 3-start_date, 4-end_date, 5-field_name
	my $act_select_statement;
	my @input_vars;
	if($level eq 'all'){
		$act_select_statement = $select_statement_all;
		push(@input_vars,$account_key,$start_date,$end_date,$field_name);

	}
	elsif($level < 100 && $level > 0){
		$act_select_statement = $select_statement_lN;
		push(@input_vars,$account_key,$level,$start_date,$end_date,$field_name);
		
	}
	elsif(!$level || $level == 0){
		# assume only cares about current account
		$act_select_statement = $select_statement_l0;
		push(@input_vars,$account_key,$start_date,$end_date,$field_name);
		
	}
	else{
		# nothing fits, return garbage
		warn "level: $level\naccount: $account_key\n";
		return "";
	}
	
	my $select_handler = $topic_handler->database_connection()->prepare($act_select_statement);
	$select_handler->execute(@input_vars);
	my ($balance);
	$select_handler->bind_col( 1, \$balance );
	my @garbate;
	while ($select_handler->fetch) {
		# the answer is $balance;
		# only 1 row should be returned
		return $balance;
	}
	return "0";  # should be undefined if this topic is not an account topic page
}
# Do markup for Split
# http://tokyo.e-flamingo.net/bin/view/Operations/OctopsSubSystemAccountingInterface
# %SPLIT{"amount" topic="%TOPIC%" account="Cash"}%
sub split_tag_renderer {
	my ($inWeb,$inTopic, $args) = @_;
	
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	
	require Foswiki::Func;
	my $tx_wt = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	my $tx_key = $topic_handler->_convert_WT_Topics_in($tx_wt);
	
	require Foswiki::Func;
	my $account_wt = Foswiki::Func::extractNameValuePair( $args, 'account' );
	my $account_key = $topic_handler->_convert_WT_Topics_in($account_wt);

	my $Splits = Foswiki::UI::Accounting::getTable('Splits');
	my $select_statement = qq/SELECT 
  sp1.amount 
FROM 
  $Splits sp1
WHERE
  sp1.transaction_key = ? AND
  sp1.accounts_key = ? ;/; # 1-tx_key, 2-accounts_key
	my $select_handler = $topic_handler->database_connection()->prepare($select_statement);
	$select_handler->execute($tx_key,$account_key);
	my ($amount);
	$select_handler->bind_col( 1, \$amount );
	while ($select_handler->fetch) {
		# the answer is $balance;
		# only 1 row should be returned
		return $amount;
	}
	return undef;
	#die "nothing(tx:$tx_key,acc:$account_key)";  # should be undefined if this topic is not an account topic page
	
}
1;
__END__
