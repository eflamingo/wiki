package Foswiki::Plugins::AccountsPlugin::DiDs;

use strict;
use Foswiki::Func();
use Foswiki::Plugins::AccountsPlugin::Orders();
use Foswiki::Plugins::AccountsPlugin::Credits();

my $keyhash = {
	'site_key' => {},
	'topics' => {},
	'webs' => {},
};
# ($web,$topic)-> $topic_key
sub _add_topic_key {
	return "die";	
}
####################################################################################################################
=pod
---+ refresh_dids

=cut

sub refresh_dids {
	my $session = shift;
	my $topic = $session->{topicName};
	my $web = $session->{webName};
	my $request = $session->{request};
	# get all of the topics from the url param
	my $did_list = $request->param('did_list');
	my @many_dids = split(',',$did_list);
	# db
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $ef_site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Webs = $topic_handler->getTableName('Webs');
	my $UH = $topic_handler->getTableName('User_History');
	my $Topics = $topic_handler->getTableName('Topics');
	my $di1 = $topic_handler->getTableName('DiD_Inventory');
	
	# the insert statement
	# full_number character varying NOT NULL,
	# owner_key uuid NOT NULL,
	# site_key uuid,
	# user_key uuid,
	
	# 1-user_key, 2-user_key, 3-finish, 4-timestamp, 5-number, 6-owner_key
	my $updateStatement = qq/UPDATE $di1 SET site_key= NULL , user_key = ? , owner_key= ?, finish = ?, timestamp_epoch = ? WHERE full_number= ? AND owner_key != ?/;
	# 1-user_key, 2-user_key, 3-number, 4-finish, 5-timestamp, 6-number
	my $insertStatement = qq/
INSERT INTO $di1 (user_key, owner_key, full_number, finish, timestamp_epoch) 
	(SELECT  ? as user_key, ? as owner_key, ? as full_number, ? as finish, ? as timestamp_epoch
		WHERE NOT EXISTS (SELECT 1 FROM $di1 WHERE full_number = ? ));/; 
	
	my $updateHandler = $topic_handler->database_connection()->prepare($updateStatement);
	my $insertHandler = $topic_handler->database_connection()->prepare($insertStatement);	
	
	
	# load all of the DiD topics
	my @meta_array;
	my @var_list;
	foreach my $did_wt (@many_dids){
		my ($did_wn,$did_tn) = Foswiki::Func::normalizeWebTopicName($web,$did_wt);
		my ($temp_meta,$temp_text) = Foswiki::Func::readTopic($did_wn,$did_tn);
		$temp_meta->putKeyed( 'FIELD', {'name'=>"LastUpdate",'title'=>"LastUpdate",'value'=>time()});
		push(@meta_array,$temp_meta);
		
		# extract the form field data from the topic
		my %form_hash;
		# Fields (Number, CountryCode, Owner, Supplier)
		my @Fields = $temp_meta->find( 'FIELD' );
		foreach my $xf (@Fields){
				$form_hash{$xf->{'name'}} = $xf->{'value'};
		}
		
		next if $form_hash{'Number'} eq '0'; # make sure we are not loading a template

		# convert the country code and number into the international number
		my $international_num = _change_num($form_hash{'CountryCode'},$form_hash{'Number'});

		# 1-owner,2-number,3-exp_date
		my $epoch_exp = Foswiki::Time::parseTime($form_hash{'Expiration'});
		# need to make sure we get the user UUID, without the web name mucking things up
		my ($owner_wn,$owner_tn) = Foswiki::Func::normalizeWebTopicName($web,$form_hash{'Owner'});
		my @temp_var = ($owner_tn,$international_num,$epoch_exp);

		push(@var_list,\@temp_var);
	}
	
	my %opts01;
	$opts01{'nocommit'} = 1;	
	eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();
			
		foreach my $temp_var_ref (@var_list){
			# 1-owner,2-number,3-exp_date
			my ($user02,$num02,$exp_date) = ($temp_var_ref->[0],$temp_var_ref->[1],$temp_var_ref->[2]);
# 1-user_key, 2-user_key, 3-finish, 4-timestamp, 5-number, 6-owner_key
			$updateHandler->bind_param( 1, $user02);
			$updateHandler->bind_param( 2, $user02);
			$updateHandler->bind_param( 3, $exp_date);
			$updateHandler->bind_param( 4, time());
			$updateHandler->bind_param( 5, $num02);
			$updateHandler->bind_param( 6, $user02);
# 1-user_key, 2-user_key, 3-number, 4-finish, 5-timestamp, 6-number
			$insertHandler->bind_param( 1, $user02);
			$insertHandler->bind_param( 2, $user02);
			$insertHandler->bind_param( 3, $num02);
			$insertHandler->bind_param( 4, $exp_date);
			$insertHandler->bind_param( 5, time());
			$insertHandler->bind_param( 6, $num02);
			
			$updateHandler->execute;
			$insertHandler->execute;
		}
		foreach my $xmeta (@meta_array){
			$xmeta->save(%opts01);
		}
		# commit the transaction
		$topic_handler->database_connection()->commit;
	};
	if ($@) {
		#die "Rollback - failed to save ($w01,$t01) for reason:\n ";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
		catch Error::Simple with {
           	throw Foswiki::OopsException(
               	'attention',
	               def    => 'save_error',
                web    => $web,
       	        topic  => $topic,
           	    params => [ $@ ]
	           );
        };
	}	
	
}

sub _change_num {
	my $country_code = shift;
	my $number = shift;
	# clean the number of any hyphens or extraneous stuff
	$number =~ s/[-*+@&]//gi;
	
	if($country_code == 1){
		# USA Number 1 forever!
		return $country_code.$number;
	}
	elsif($country_code == 81){
		# Japan
		# take off the first 0
		$number = substr $number, 1;
		return $country_code.$number;
	}
	else{
		return undef;
	}
}

# this is for the DiD View Page on e-flamingo.net
sub did_search {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins;
	my $session = $Foswiki::Plugins::SESSION;
	require Foswiki::Func;
	my $field = Foswiki::Func::extractNameValuePair( $args, 'Field' );
	my $user_key = $session->{user};
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();

  
	my $di1 = $topic_handler->getTableName('DiD_Inventory');
	my $si1 = $topic_handler->getTableName('Site_Inventory');
	my $Sites = $topic_handler->getTableName('Sites');
	my $selectStatement = qq/SELECT 
  di1.full_number, sites.current_site_name
FROM 
  $di1 di1
	FULL OUTER JOIN ($si1 s1 INNER JOIN $Sites sites ON s1.site_key = sites."key") ON di1.site_key = s1.site_key
WHERE
  di1.owner_key = ? OR s1.owner_key = ? ;/; # 1-owner_key, 2-owner_key
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($user_key,$user_key);
	my ($number,$site_name);
	$selectHandler->bind_col( 1, \$number );
	$selectHandler->bind_col( 2, \$site_name );

	my @site_names;
	my @return_hashes;
	my %check_site_doubles;
	while ($selectHandler->fetch) {
		my %hash01;
		$hash01{'number'} = $number;
		$hash01{'site_name'} = $site_name;
		push(@return_hashes,\%hash01) if $number;
		push(@site_names,$site_name) if $site_name && !$check_site_doubles{$site_name};
		$check_site_doubles{$site_name} = 1 if $site_name;
	}
	
	my @rows;
	foreach my $singleHash (@return_hashes){
		push(@rows,_format_row($singleHash->{'number'},$singleHash->{'site_name'},\@site_names));
	}
	return join("\n",@rows)."\n";
}
####################################################################################################################
=pod
---+ _format_row
formats row on DiD Manager View
=cut

sub _format_row {
	my $number = shift;
	my $site_name = shift;
	my $sarray_ref = shift;
	my @sites = ('');
	# the user may not have any sites
	@sites = @$sarray_ref if $sarray_ref;
	
	
	my $return_string = "";
	my @cells;
	# Insert the First and Second columns | *Number* | *Current Destination* | 
	# add number
	push(@cells," $number ");
	# add site or the user login name if the number is directed at the user
	push(@cells," [[http://$site_name][$site_name]] ") if $site_name;
	push(@cells," %USERINFO{ format=\"\$username\" }% ") unless $site_name;
	
	# For the Third column, | *New Destination* |, generate a select form
	my @select_array;
	$select_array[0] = '<option value="YOU">%USERINFO{ format="$username" }%</option>';
	foreach my $sn01 (@sites){
		my $x01 = '<option value="'.$sn01.'">'.$sn01.'</option>';
		push(@select_array,$x01); 
	}
	my $selector_html = ' <form action=\'%SCRIPTURL{"accounts"}%/%BASEWEB%/%BASETOPIC%\' name="savedFromTemplate" method="POST">';
	$selector_html .= '<input type="hidden" name="action" value="change_did_destination" />';
	$selector_html .= '<input type="hidden" name="did" value="'.$number.'" />';
	$selector_html .= '<select size="1" name="new_destination" >'.join(' ',@select_array).'</select>';
	$selector_html .= '<input type="submit" value="Change Destination"/ ></form> ';
	push(@cells,$selector_html);
	
	$return_string = '|'.join('|',@cells).'|';
	return $return_string;
}
####################################################################################################################
=pod
---+ change_did_destination
 "did" is the number, new_destination is either YOU (the user), or a site_name
=cut

sub change_did_destination {
	my $session = shift;
	my $request = $session->{request};
	my ($web,$topic) = ($session->{webName},$session->{topicName});
	my $user_key = $session->{user};
	my $full_number = $request->param('did');
	
	# the new_dest is either YOU or a site_name (full domain name, probably)
	my $new_dest = $request->param('new_destination');
	
	# update DiD Inventory Table to point to the correct site (or user)
	# get the db handler
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	
	my $did1 = $topic_handler->getTableName('DiD_Inventory');
	my $Sites = $topic_handler->getTableName('Sites');
	my $si1 = $topic_handler->getTableName('Site_Inventory');
	# make sure the owner_key is match for security reasons
	my $updateStatement;
	if($new_dest eq 'YOU'){
		$updateStatement = qq/
			UPDATE $did1 SET (user_key, site_key) = 
	(owner_key, NULL)
WHERE owner_key = ? AND full_number = ?;/; # 1-owner_key, 2-full_number
	}
	else{
		$updateStatement = qq/
			UPDATE $did1 di1 SET user_key = NULL, site_key = s1."key" 
				FROM $Sites s1 INNER JOIN $si1 si1 ON si1.site_key = s1."key"
  			WHERE si1.owner_key = ? AND di1.owner_key = si1.owner_key AND di1.full_number = ? AND s1.current_site_name = ? ;/; # 1-owner_key, 2-full_number, 3-site_name
	}
	my $updateHandler = $topic_handler->database_connection()->prepare($updateStatement);
	
	eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();
		 
		if($new_dest eq 'YOU'){
			# number points to user
			$updateHandler->execute($user_key,$full_number);
		}
		else{
			# number points to site
			$updateHandler->execute($user_key,$full_number,$new_dest);
		}
		
		# commit the transaction
		$topic_handler->database_connection()->commit;
	};
	if ($@) {
		#die "Rollback - failed to save ($w01,$t01) for reason:\n ";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
		catch Error::Simple with {
           	throw Foswiki::OopsException(
               	'attention',
	               def    => 'save_error',
                web    => $web,
       	        topic  => $topic,
           	    params => [ $@ ]
	           );
        };
	}	
}

####################################################################################################################
=pod
---+ order_did (anything related to paying cash and the user's account is credited)

=cut

sub order_did {
	my $session = shift;
	my $request = $session->{request};
	my ($web,$topic) = ($session->{webName},$session->{topicName});
	my $user_key = $session->{user};
	my $current_time = time();
	my @choices = ($request->param('choice1'),$request->param('choice2'),$request->param('choice3'));
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();	
	
	my $gc_product_topic = $request->param('product_topic');
	my ($gcWeb,$gcTopic) = Foswiki::Func::normalizeWebTopicName($web,$gc_product_topic);
	my ($gcMeta,$gcText) = Foswiki::Func::readTopic($gcWeb,$gcTopic);
	# Fields (Number, CountryCode, Owner, Supplier,JPY)
	my @gcFields;
	my %gc_form_hash;
	my @gcFields = $gcMeta->find( 'FIELD' );
	foreach my $xf (@gcFields){
			$gc_form_hash{$xf->{'name'}} = $xf->{'value'};
	}
	
	# Figure out the contract types
	my ($contract_wn,$contract_tn) = Foswiki::Func::normalizeWebTopicName($web,$gc_form_hash{'TermsOfService'}) ;
	my $contract_throw = $handler->LoadTHRow($contract_wn,$contract_tn);
	my $contract_thkey = $contract_throw->{'key'};

	# Get the Product T_H_key (from the gift card topic)
	my $product_throw = $handler->LoadTHRow($gcWeb,$gcTopic);
	my $product_thkey = $product_throw->{'key'};
	
	# create order invoice page
	my $invoice_topic = Foswiki::Meta::->new($session,$web,$topic.'Order'.$current_time);
	my ($i,$t_exists) = (0,1);
	while(!$t_exists){
		my $throw01 = $handler->LoadTHRow($gcWeb,$gcTopic.'Order'.$current_time.'N'.$i);
		$t_exists = 0 unless $handler->fetchTopicKeyByWT($gcWeb,$gcTopic.'Order'.$current_time.'N'.$i);
		$i += 1;
		die "Overloop" if $i>20;
	}
	$invoice_topic->web($gcWeb);
	$invoice_topic->topic($gcTopic.'Order'.$current_time.'N'.$i);
	my $invoice_text = '%INCLUDE{"OrderInvoiceTemplateView"}%';
	$invoice_text .= "\n   * Phone Number Choices:\n      1. ".$choices[0]."\n      1. ".$choices[1]."\n      1. ".$choices[2] unless @choices;
	# make sure to allow the user to see the invoice later
	my ($uwikiW,$uwikiT) = Foswiki::Func::normalizeWebTopicName($web,$session->{users}->getWikiName($user_key));
	$invoice_text .= "\n<!--\n   * ALLOWTOPICVIEW = $uwikiW.$uwikiT\n-->";
	$invoice_topic->text($invoice_text);
	
	my $amount = _calculate_setup_price($gc_form_hash{'JPY'},$gc_form_hash{'JPYSetup'});
	
	
	# db prep, turn off autocommits so we can use transactions
	$handler->database_connection()->{AutoCommit} = 0;
	$handler->database_connection()->{RaiseError} = 1;
	require Foswiki::Plugins::AccountsPlugin::Credits;
	eval{
		# defer constraints
		$handler->set_to_deferred();
		# place an order under $user_key's name
		# a contract and product_type should be embedded in the order object
		my $order = Foswiki::Plugins::AccountsPlugin::Orders::->place_order({'product_type' => 'Credits', 'contract_topic'=> $contract_thkey, 
					'handler'=>$handler, 'owner' => $user_key, 'product_topic' => $product_thkey});
		# we have to confirm payment of JPY,etc before we can fill this order
		$order->fill_date(0);
		$order->contract->start(0);
		# save the order
		$order->contract->save;
		$order->save;
		# ($handler, order_obj, amount,currency)-> adds credits to the user's accounts
		Foswiki::Plugins::AccountsPlugin::Credits::_deduct_credits_from_account( $handler, $order->product_topic, $order->contract->owner ,$amount, 'JPY');
		
		# set nocommit and preseed_topic_key options for DBIStoreContrib save
		my %opts;
		$opts{'nocommit'} = 1;
		$opts{'preseed_topic_key'} = $order->key;
		$opts{'handler'} = $handler;
		
		$invoice_topic->save(%opts);
		
		$handler->database_connection()->commit;		
	};
	if ($@) {
		die "data error: $@";
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Order did not go through.  Sorry.',
                params => ['order_credit']
		);
		
	}
	my $viewURL = $session->getScriptUrl( 1, 'view', $web, $topic );
	$session->redirect( $session->redirectto($viewURL), undef, 1 );
	# mark order as filled when receipt of payment is confirmed manually
	
}

# (monthly price,setup price)->the actual setup price
sub _calculate_setup_price {
	my $monthly = shift;
	my $setup = shift;

	return 2*$monthly unless $setup;
	return $setup if $setup;
}


####################################################################################################################
=pod
---+ all_did_seconds
full_number -> [owner_key,site_key,user_key,start,end]
=cut

sub all_did_seconds {
	my ($start_epoch,$end_epoch) = @_;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $DiD_Inventory = $topic_handler->getTableName('DiD_Inventory');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	
	my $selectStatement = qq^
	SELECT did.full_number, did.owner_key, did.site_key, did.user_key, did.timestamp_epoch, did.finish
	FROM $DiD_Inventory did
	WHERE did.timestamp_epoch < ?
	^; # 1-end_time
	
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($end_epoch);
	my ($full_number,$owner_key,$site_key,$user_key,$did_start_epoch,$did_end_epoch);
	$selectHandler->bind_col( 1, \$full_number );
	$selectHandler->bind_col( 2, \$owner_key );
	$selectHandler->bind_col( 3, \$site_key );
	$selectHandler->bind_col( 4, \$user_key );
	$selectHandler->bind_col( 5, \$did_start_epoch );
	$selectHandler->bind_col( 6, \$did_end_epoch );
	
	my $did_hash;
	while ($selectHandler->fetch) {
		$did_hash->{$full_number}->{'owner_key'} = $owner_key;
		$did_hash->{$full_number}->{'site_key'} = $site_key;
		$did_hash->{$full_number}->{'user_key'} = $user_key;
		$did_hash->{$full_number}->{'start_epoch'} = $did_start_epoch;
		$did_hash->{$full_number}->{'end_epoch'} = $did_end_epoch;
	}
	return $did_hash;
}


####################################################################################################################
=pod
---+ all_billed_seconds
(call_uuid)->[
  call_history.answer_epoch,
  call_history.caller_key,
  call_history.callee_key,
  call_history.owner_key,
  call_history.source_gateway,
  call_history.source_gateway_destination,
  call_history.destination_gateway,
  call_history.destination_gateway_destination,
  call_history.billsec,
  rhmax.rate_currency||' '||ceil(call_history.billsec/60.0) * rhmax.rate||'  @  '||rhmax.rate as cost
]
=cut

sub all_billed_seconds {
	my ($start_epoch,$end_epoch) = @_;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $DiD_Inventory = $topic_handler->getTableName('DiD_Inventory');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	
	###### Caller->PTSN or PTSN->Callee #######
	my $selectStatementCallerCallee = qq^
SELECT
  call_history.call_uuid,
  call_history.answer_epoch,
  call_history.caller_key,
  call_history.callee_key,
  call_history.owner_key,
  call_history.source_gateway,
  call_history.source_gateway_destination,
  call_history.destination_gateway,
  call_history.destination_gateway_destination,
  call_history.billsec,
  rhmax.rate_currency||';'||ceil(call_history.billsec/60.0) * rhmax.rate||';'||rhmax.rate as cost
FROM 
(
  
SELECT 
  ch.call_uuid as call_uuid,
  ch.caller_key as caller_key, 
  ch.callee_key as callee_key,
  ch.billsec as billsec,
  array_to_string(array_agg(si.owner_key), ';') as owner_key,
  did.gateway as source_gateway,
  did.gateway_destination as source_gateway_destination,
  ch.gateway as destination_gateway,
  ch.gateway_destination as destination_gateway_destination,
  ch.answer_epoch as answer_epoch
FROM 
freeswitch."CDR_Topic_Mapper" cdr
  INNER JOIN (freeswitch."Call_History" ch 
         LEFT JOIN accounts."DiD_Inventory" did ON ch.destination_number = did.full_number ) 
      ON cdr.call_history_key = ch.call_uuid
  LEFT JOIN (foswiki."Webs" w1
         INNER JOIN foswiki."Topics" t1 ON w1."key" = t1.current_web_key
         INNER JOIN accounts."Site_Inventory" si ON si.site_key = w1.site_key
         INNER JOIN foswiki."Sites" s1 ON s1."key" = w1.site_key )
      ON t1."key" = cdr.topic_key AND s1.current_site_name != 'e-flamingo.net'
WHERE
  ch.answer_epoch >= ?  AND ch.answer_epoch <= ? AND
-- Both caller->PTSN and PTSN->callee cases, but not PTSN->PTSN cases
(ch.caller_key IS NOT NULL OR ch.callee_key IS NOT NULL ) AND (ch.caller_key IS NULL OR ch.callee_key IS NULL ) AND ch.billsec > 0
GROUP BY ch.call_uuid,ch.caller_key,ch.callee_key,ch.billsec,  did.gateway,
  did.gateway_destination, ch.gateway, ch.gateway_destination,ch.answer_epoch
) as call_history,
accounts."Rate_History" rhmax 
  INNER JOIN accounts."Rate_History" rhd ON rhmax.gateway = rhd.gateway AND rhmax.regex = rhd.regex
WHERE
-- only get rates effective at the time of the call
 rhd.as_of_epoch < call_history.answer_epoch AND
-- match the gateways and regex (mobile, landline, etc)
 (call_history.destination_gateway = rhmax.gateway AND call_history.destination_gateway_destination ~ rhmax.regex)
 OR
 (call_history.source_gateway = rhmax.gateway AND call_history.source_gateway_destination ~ rhmax.regex)

GROUP BY
    call_history.source_gateway,call_history.source_gateway_destination,
    call_history.destination_gateway,  call_history.destination_gateway_destination,
  call_history.billsec, rhmax.rate,rhmax.rate_currency, rhmax.as_of_epoch,call_history.answer_epoch,  call_history.caller_key,
  call_history.callee_key,  call_history.owner_key, call_history.call_uuid
HAVING
  rhmax.as_of_epoch = MAX(rhd.as_of_epoch)

ORDER BY call_history.answer_epoch ASC
;
	^; # 1-start_time,2-end_time
	
	my $selectHandlerCallerCallee = $topic_handler->database_connection()->prepare($selectStatementCallerCallee);
	
	###### PTSN->PTSN #######
	my $selectStatementPTSNPTSN = qq^
SELECT
  call_history.call_uuid,
  call_history.answer_epoch,
  call_history.caller_key,
  call_history.callee_key,
  call_history.owner_key,
  call_history.source_gateway,
  call_history.source_gateway_destination,
  call_history.destination_gateway,
  call_history.destination_gateway_destination,
  call_history.billsec,
  rhmax1.rate_currency||';'||ceil(call_history.billsec/60.0) * rhmax1.rate||';'||rhmax1.rate as source_rate,
  rhmax2.rate_currency||';'||ceil(call_history.billsec/60.0)  * rhmax2.rate||';'||rhmax2.rate as destination_rate,
  call_history.did_owner_key
FROM 
(
SELECT 
  ch.call_uuid as call_uuid,
  ch.caller_key as caller_key, 
  ch.callee_key as callee_key,
  ch.billsec as billsec,
  array_to_string(array_agg(si.owner_key), ';') as owner_key,
  did.gateway as source_gateway,
  did.gateway_destination as source_gateway_destination,
  ch.gateway as destination_gateway,
  ch.gateway_destination as destination_gateway_destination,
  ch.answer_epoch as answer_epoch,
  did.owner_key as did_owner_key
  
FROM 
freeswitch."CDR_Topic_Mapper" cdr
  INNER JOIN (freeswitch."Call_History" ch 
         LEFT JOIN accounts."DiD_Inventory" did ON ch.destination_number = did.full_number ) 
      ON cdr.call_history_key = ch.call_uuid
  LEFT JOIN (foswiki."Webs" w1
         INNER JOIN foswiki."Topics" t1 ON w1."key" = t1.current_web_key
         INNER JOIN accounts."Site_Inventory" si ON si.site_key = w1.site_key
         INNER JOIN foswiki."Sites" s1 ON s1."key" = w1.site_key )
      ON t1."key" = cdr.topic_key AND s1.current_site_name != 'e-flamingo.net'
WHERE
  ch.answer_epoch >= ?  AND ch.answer_epoch <= ? AND
-- looking for PTSN->PTSN
  ch.caller_key IS NULL AND ch.callee_key IS NULL AND ch.billsec > 0
GROUP BY ch.call_uuid,ch.caller_key,ch.callee_key,ch.billsec,  did.gateway,
  did.gateway_destination, ch.gateway, ch.gateway_destination,ch.answer_epoch,did.owner_key

) as call_history,
accounts."Rate_History" rhmax1
  INNER JOIN accounts."Rate_History" rhd1 ON rhmax1.gateway = rhd1.gateway AND rhmax1.regex = rhd1.regex,
accounts."Rate_History" rhmax2
  INNER JOIN accounts."Rate_History" rhd2 ON rhmax2.gateway = rhd2.gateway AND rhmax2.regex = rhd2.regex
WHERE
-- only get rates effective at the time of the call
 rhd1.as_of_epoch < call_history.answer_epoch AND rhd2.as_of_epoch < call_history.answer_epoch AND
-- match the gateways and regex (mobile, landline, etc)
(
 (call_history.destination_gateway = rhmax2.gateway AND call_history.destination_gateway_destination ~ rhmax2.regex)
 AND
 (call_history.source_gateway = rhmax1.gateway AND call_history.source_gateway_destination ~ rhmax1.regex)
)

GROUP BY
    call_history.source_gateway,call_history.source_gateway_destination,
    call_history.destination_gateway,  call_history.destination_gateway_destination,
  call_history.billsec, rhmax1.rate,rhmax1.rate_currency, rhmax1.as_of_epoch,rhmax2.rate,rhmax2.rate_currency, 
  rhmax2.as_of_epoch,call_history.answer_epoch, call_history.caller_key, call_history.callee_key, call_history.owner_key,call_history.call_uuid,
  call_history.did_owner_key
HAVING
  rhmax1.as_of_epoch = MAX(rhd1.as_of_epoch) AND rhmax2.as_of_epoch = MAX(rhd2.as_of_epoch)
ORDER BY call_history.answer_epoch ASC
;
	^; # 1-start_time,2-end_time
	my $selectHandlerPTSNPTSN = $topic_handler->database_connection()->prepare($selectStatementPTSNPTSN);
	
	# define return hash
	my $cdr_hash;
	my $i = 0;
	my (@costA,@costB);
	# $selectHandlerCallerCallee, $selectHandlerPTSNPTSN
	$selectHandlerCallerCallee->execute($start_epoch,$end_epoch);
	$selectHandlerPTSNPTSN->execute($start_epoch,$end_epoch);
	
	my ($call_uuid,$answer_epoch,$caller_key,$callee_key,$owner_key,$sg,$sgdest,$dg,$dgdest,$billsec,$cost_a,$cost_b,$did_owner_key);
	$selectHandlerCallerCallee->bind_col( 1, \$call_uuid );
	$selectHandlerCallerCallee->bind_col( 2, \$answer_epoch );
	$selectHandlerCallerCallee->bind_col( 3, \$caller_key );
	$selectHandlerCallerCallee->bind_col( 4, \$callee_key );
	$selectHandlerCallerCallee->bind_col( 5, \$owner_key );
	$selectHandlerCallerCallee->bind_col( 6, \$sg );
	$selectHandlerCallerCallee->bind_col( 7, \$sgdest );
	$selectHandlerCallerCallee->bind_col( 8, \$dg );
	$selectHandlerCallerCallee->bind_col( 9, \$dgdest );
	$selectHandlerCallerCallee->bind_col( 10, \$billsec );
	$selectHandlerCallerCallee->bind_col( 11, \$cost_a );
	my ($usercalleecaller,$order_user_hash);
	while ($selectHandlerCallerCallee->fetch){
		# either the caller or callee made the call (WHERE clause insures one or the other, but not both)
		$usercalleecaller = $caller_key if $caller_key;
		$usercalleecaller = $callee_key unless $caller_key;
		$order_user_hash->{$usercalleecaller} = 0 unless $order_user_hash->{$usercalleecaller};
		
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'answer_epoch'} = $answer_epoch;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'caller_key'} = $caller_key;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'callee_key'} = $callee_key;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'owner_key'} = $owner_key;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'source_gateway'} = $sg;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'source_gateway_destination'} = $sgdest;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'destination_gateway'} = $dg;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'destination_gateway_destination'} = $dgdest;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'billsec'} = $billsec;
		
		# currency;cost;rate
		@costA = split(';',$cost_a);
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_a_currency'} = $costA[0];
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_a_cost'} = $costA[1];
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_a_rate'} = $costA[2];
		
		# make some numerical index for later
		$cdr_hash->{'order'}->{$i} = $call_uuid;
		$cdr_hash->{$usercalleecaller}->{'order'}->{$order_user_hash->{$usercalleecaller}} = $call_uuid;
		
		$i++;
		$order_user_hash->{$usercalleecaller} += 1;
	}
	$usercalleecaller = "";
	
	$selectHandlerPTSNPTSN->bind_col( 1, \$call_uuid );
	$selectHandlerPTSNPTSN->bind_col( 2, \$answer_epoch );
	$selectHandlerPTSNPTSN->bind_col( 3, \$caller_key );
	$selectHandlerPTSNPTSN->bind_col( 4, \$callee_key );
	$selectHandlerPTSNPTSN->bind_col( 5, \$owner_key );
	$selectHandlerPTSNPTSN->bind_col( 6, \$sg );
	$selectHandlerPTSNPTSN->bind_col( 7, \$sgdest );
	$selectHandlerPTSNPTSN->bind_col( 8, \$dg );
	$selectHandlerPTSNPTSN->bind_col( 9, \$dgdest );
	$selectHandlerPTSNPTSN->bind_col( 10, \$billsec );
	$selectHandlerPTSNPTSN->bind_col( 11, \$cost_a );
	$selectHandlerPTSNPTSN->bind_col( 12, \$cost_b );
	$selectHandlerPTSNPTSN->bind_col( 13, \$did_owner_key );
	while ($selectHandlerPTSNPTSN->fetch){
		# figure out who gets billed
		$usercalleecaller = $owner_key;
		$usercalleecaller = $did_owner_key unless $usercalleecaller;
		$order_user_hash->{$usercalleecaller} = 0 unless $order_user_hash->{$usercalleecaller};
		
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'answer_epoch'} = $answer_epoch;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'caller_key'} = $caller_key;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'callee_key'} = $callee_key;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'owner_key'} = $owner_key;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'source_gateway'} = $sg;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'source_gateway_destination'} = $sgdest;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'destination_gateway'} = $dg;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'destination_gateway_destination'} = $dgdest;
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'billsec'} = $billsec;
		# currency;cost;rate
		@costA = split(';',$cost_a);
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_a_currency'} = $costA[0];
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_a_cost'} = $costA[1];
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_a_rate'} = $costA[2];
		# currency;cost;rate
		@costB = split(';',$cost_b);
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_b_currency'} = $costB[0];
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_b_cost'} = $costB[1];
		$cdr_hash->{$usercalleecaller}->{$call_uuid}->{'cost_b_rate'} = $costB[2];
		
		$cdr_hash->{'order'}->{$i} = $call_uuid;
		$cdr_hash->{$usercalleecaller}->{'order'}->{$order_user_hash->{$usercalleecaller}} = $call_uuid;
		
		$i++;
		$order_user_hash->{$usercalleecaller} += 1;
		
		# store the number of calls (will be overwritten until last call)
		$order_user_hash->{$usercalleecaller}->{'number_of_calls'} = $order_user_hash->{$usercalleecaller};
	}
	$cdr_hash->{'number_of_calls'} = $i; # includes $i++ b/c index started at 0
	return $cdr_hash;

}


##########################################################################
=pod
---+ did_info
%DIDINFO{"full_number/owner/forward_site" topic="did_topic"}%
=cut

sub did_info {
	my ($inWeb,$inTopic, $args) = @_;
	my $session = $Foswiki::Plugins::SESSION;
	
	# get the Order web,topic pair
	require Foswiki::Func;
	my $did_topic_WT = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	$did_topic_WT = $session->{webName}.'.'.$session->{topicName} unless $did_topic_WT;
	
	my $main_arg = Foswiki::Func::extractNameValuePair( $args );
	
	# get the order id
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	my $did_topic = $topic_handler->_convert_WT_Topics_in($did_topic_WT);
	
	return undef unless $did_topic;

	my $Sites = $topic_handler->getTableName('Sites');
	my $SiteInventory = $topic_handler->getTableName('Site_Inventory');
	my $DiDInventory = $topic_handler->getTableName('DiD_Inventory');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	# get the site info, load it into cache?
	my $selectStatement = qq/SELECT 
  sididinv.topic_key, 
  didinv.full_number, 
  didinv.owner_key, 
  s1.current_site_name,
  s1."key"
FROM 
  $DiDInventory didinv
	LEFT JOIN $Sites s1 ON s1."key" = didinv.site_key
	LEFT JOIN $SiteInventory sididinv ON didinv.site_key = sididinv.site_key
WHERE 
 didinv.topic_key = ?
  ;/;
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($did_topic);
	my ($site_topic_key,$full_number,$owner_key,$current_site_name,$site_key);
	$selectHandler->bind_col( 1, \$site_topic_key );
	$selectHandler->bind_col( 2, \$full_number );
	$selectHandler->bind_col( 3, \$owner_key );
	$selectHandler->bind_col( 4, \$current_site_name );
	$selectHandler->bind_col( 5, \$site_key );
	
	while ($selectHandler->fetch) {
		 
		my $xl0223 = $topic_handler->convert_Var('WT','Users',$owner_key,'out');
		my ($owner_web,$owner_topic) = ($xl0223->[0],$xl0223->[1]);
		$topic_handler->putMemcached('did_inventory',$full_number.'owner_key',$owner_key);
		$topic_handler->putMemcached('did_inventory',$full_number.'owner_WT',$owner_web.'.'.$owner_topic);
	
		my ($site_web,$site_topic);
		if($site_key){
			# if site_key, then did number must be pointing at site, not number
			$topic_handler->putMemcached('did_inventory',$full_number.'site_key',$site_key);
			$topic_handler->putMemcached('did_inventory',$full_number.'site_name',$current_site_name);
			my $temp_array_ref = $topic_handler->convert_Var('WT','Topics',$site_topic_key,'out');
			($site_web,$site_topic) = ($temp_array_ref->[0],$temp_array_ref->[1]);
			$topic_handler->putMemcached('did_inventory',$full_number.'site_topic',$site_web.'.'.$site_topic);
		}

		else{
			# else, did number must be pointing at user on e-flamingo.net
			$topic_handler->putMemcached('did_inventory',$full_number.'user_key',$owner_key);
		}

		return $full_number if $main_arg eq 'full_number';
		return $owner_web.'.'.$owner_topic if $main_arg eq 'owner';
		return $site_web.'.'.$site_topic if $main_arg eq 'forward_site' && $site_web && $site_topic;

	}
	return '';
}
# called from MetaPreference SaveHandler
sub changeOwnerViaMetaPreference{
	my ($handler,$name,$type,$value,$topicObject,$cUID,$th_row_ref,$meta_ref) = @_;
	return 1 unless  $name eq 'DIDOWNER';
	my $badvarbool = 0;
	if(!$name || !$value){
		$badvarbool = 1;
	}
	#return 0 if $badvarbool;
	die "no name or value" if $badvarbool;
	# make sure the $value is a user
	my $user_key = $handler->convert_Var('WT','Users',$value,'in');
	die "bad user key" unless $user_key;
	
	my $DiDInventory = $handler->getTableName('DiD_Inventory');
	my $Topics = $handler->getTableName('Topics');
	# when updating, let's avoid updating if the owner is not changing
	my $updateStatement = qq/
UPDATE $DiDInventory
SET
  owner_key = ?
WHERE
  full_number = (
SELECT 
  did1.full_number
FROM 
  $DiDInventory did1
WHERE 
  did1.topic_key = ? AND did1.owner_key != ? );/; # 1-new_owner_key, 2-topic_key of DiD, 3-new_owner_key
	my $updateHandler = $handler->database_connection()->prepare($updateStatement);
	$updateHandler->execute($user_key,$th_row_ref->{'topic_key'},$user_key);
	return 1;
}


1;
__END__
%USERINFO{ format="$username" }%
<form action='%SCRIPTURL{"save"}%/%BASEWEB%/' name="savedFromTemplate" method="POST">
<input type="hidden" name="did" value="$number" />  
<select size="1" name="new_destination" ><option value="81">Japan</option></select>
<option value="YOU">%USERINFO{ format=\"\$username\" }%</option>
<option value="$site_name">$site_name</option>
<input type="submit" value="Add DiD"/ > 
</form>
---+ Sample DiD Form
Number 	2022497512
CountryCode 	1
Owner 	admin, Unknown
Supplier 	iCall 

---+ Find Topics with DiD Forms
SELECT 
  t_target."key"
FROM 
  
  foswiki."Dataform_Data_History" dfdata
	INNER JOIN foswiki."Topic_History" dfdef ON dfdef."key" = dfdata.definition_key
	INNER JOIN foswiki."Topics" t_target ON t_target.link_to_latest = dfdata.topic_history_key
WHERE 
  dfdef.topic_key = ?;
