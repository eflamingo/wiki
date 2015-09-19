package Foswiki::Plugins::AccountsPlugin::Sites;

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

sub order_site {
	my $session = shift;
	my $request = $session->{request};
	my ($web,$topic) = ($session->{webName},$session->{topicName});
	my $user_key = $session->{user};
	my $current_time = time();
	my $requested_site_name = $request->param('site_name');
	my @user_emails = ($request->param('user_email_2'),$request->param('user_email_3'),$request->param('user_email_4'));
	my @user_logins = ($request->param('user_login_2'),$request->param('user_login_3'),$request->param('user_login_4'));	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();	

	
	my $gc_product_topic = $request->param('product_topic');
	my ($gcWeb,$gcTopic) = Foswiki::Func::normalizeWebTopicName($web,$gc_product_topic);
	my ($gcMeta,$gcText) = Foswiki::Func::readTopic($gcWeb,$gcTopic);
	# Fields (JPY, JPYSetup, TermsOfService)
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
	
	# create order invoice page from an invoice template topic
	my $invoice_topic = Foswiki::Meta::->new($session,$web,$topic.'Order'.$current_time);
	$invoice_topic->web('Main');
	$invoice_topic->topic('OrderInvoiceTemplateView');
	$invoice_topic->load();
	my ($i,$t_exists) = (0,1);
	while(!$t_exists){
		my $throw01 = $handler->LoadTHRow($gcWeb,$gcTopic.'Order'.$current_time.'N'.$i);
		$t_exists = 0 unless $handler->fetchTopicKeyByWT($gcWeb,$gcTopic.'Order'.$current_time.'N'.$i);
		$i += 1;
		die "Overloop" if $i>20;
	}
	$invoice_topic->web($gcWeb);
	$invoice_topic->topic($gcTopic.'Order'.$current_time.'N'.$i);
	
	my $invoice_text = $invoice_topic->text;
	$invoice_text .= "\n   * Local SiteName = ".$requested_site_name;
	$invoice_text .= "\n   * Local UserNames = ".join(",",@user_logins) unless @user_logins;
	$invoice_text .= "\n   * Local UserEmails = ".join(",",@user_emails) unless @user_emails;

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

# -------------- Creating a new Wiki ------------------
sub deliver_site {
	my $session = shift;
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};
	my $current_time = time();
	
}


#----------------------- Miscellaneous Functions -------------------------------------
# ($topic_obj,$field_name)-> $amount
sub _get_Field_Value {
	my $topicObject = shift;
	my $field_name = shift;
	my @fields = $topicObject->find( 'FIELD' );
	my $value;
	foreach my $field (@fields) {
		$value = $field->{'value'} if $field->{'name'} eq $field_name;
	}
	return $value;
}

##########################################################################
=pod
---+ consume_withdrawal
done by admin, creates and updates invoices
=cut
# -------------- Updating tokyo.e-flamingo.net ------------------
# most of this function was copied from Users.pm user_update function
sub refresh_sites {
	my $session = shift;
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};
	require Foswiki::Time;
	my $current_time = time();
	# get the db handler
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Webs = $topic_handler->getTableName('Webs');
	my $UH = $topic_handler->getTableName('User_History');
	my $Topics = $topic_handler->getTableName('Topics');
	my $SI01 = $topic_handler->getTableName('Site_Inventory');
	my $did1 = $topic_handler->getTableName('DiD_Inventory');
	# find all sites (but not e-flamingo.net)
	# the Sites table info is copied into the Coverage Web Site Inventory Database (does not include owners or exp dates)
	# this does a Join with Sites (site_key, always returns) LJ Topics (topic_key) LJ Site_Inventory (owner_key)    LJ = left join)
	my $selectStatement = qq/SELECT 
  s1.current_site_name as site_name,
  s1."key" as site_key,
  regexp_replace(s1."key"::text, '-', '','g') as clean_site_key,
  t2."key" as topic_key,
  t2.link_to_latest as th_key,
  si1.owner_key,
  regexp_replace(si1.owner_key::text, '-', '','g') as clean_owner_key
FROM 
  $Sites s1 
    LEFT JOIN ($Topics t2
		INNER JOIN ($Webs w2 INNER JOIN $Sites s2 ON w2.site_key = s2."key" AND s2.current_site_name = 'tokyo.e-flamingo.net')
			ON w2."key" = t2.current_web_key AND w2.current_web_name = 'Coverage')
		ON t2.current_topic_name = foswiki.sha1bytea(regexp_replace(s1."key"::text, '-', '','g'))
	LEFT JOIN $SI01 si1 ON s1."key" = si1.site_key
WHERE   s1.current_site_name != 'e-flamingo.net';/;
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute;
	my ($site_name,$site_key,$clean_site_key,$topic_key,$th_key,$owner_key,$clean_owner_key);
	$selectHandler->bind_col( 1, \$site_name );
	$selectHandler->bind_col( 2, \$site_key );
	$selectHandler->bind_col( 3, \$clean_site_key );
	$selectHandler->bind_col( 4, \$topic_key );
	$selectHandler->bind_col( 5, \$th_key );
	$selectHandler->bind_col( 6, \$owner_key );
	$selectHandler->bind_col( 7, \$clean_owner_key );
	my $mapper = {
		'current_site_name' => "SiteURL",
		'owner_key' => "Owner",
		'finish' => "Expiration",
		'timestamp_epoch' => "LastUpdate"
	};
	my @meta_list;
	
	my @Fields;
	my %form_hash;
	
	my @dbi_list;
	my @dbi_inserts;
	my @dbi_updates;
	my ($insertHandler,$updateHandler,$insertStatement,$updateStatement);
	
	# all data from the wiki page in Coverage is copied into the Site Inventory (for newly created sites) via Inserts
	# 1-site_key,2-owner_key,3-timestamp,4-finish
	$insertStatement = qq/INSERT INTO $SI01 (site_key, owner_key, timestamp_epoch, finish) VALUES (?,?,?,?);/;
	$insertHandler = $topic_handler->database_connection()->prepare($insertStatement); 
	
	# the owner and expiration data is copied from the Coverage Web Site Inventory Database
	#					to the Sites_Inventory Table via Updates (only for existing sites)
	# 1-owner_key, 2-updated_time, 3-expiration, 4-site_key, 5-owner_key, 6-expiration
	$updateStatement = qq/UPDATE $SI01 SET owner_key=?, timestamp_epoch=?, finish=?  
								WHERE site_key = ? AND (owner_key != ? OR finish != ?);/;
	$updateHandler = $topic_handler->database_connection()->prepare($updateStatement);
	my @updated_sites;
	while ($selectHandler->fetch) {
		my ($temp_meta,$temp_text,$temp_web,$temp_topic);
		my (@update_array,@insert_array);
		# $site_name might be new as well..., update the topic
		
		# btw si => site_inventory row
		if($topic_key && $owner_key){
			# topic exists, si row exists
			# 1. load topic (contains new owner_key, new expiration_date)
			my $crap001 = $topic_handler->_convert_WT_Topics_out($topic_key);
			($temp_web,$temp_topic) = ($crap001->[0],$crap001->[1]);
			#($temp_web,$temp_topic) = $topic_handler->_convert_WT_Topics_out($topic_key);
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
			@Fields = $temp_meta->find( 'FIELD' );
			foreach my $xf (@Fields){
				$form_hash{$xf->{'name'}} = $xf->{'value'};
			}
			# 2. update si
			my $epoch_exp = Foswiki::Time::parseTime($form_hash{'Expiration'});
			$epoch_exp = time() unless $form_hash{'Expiration'};
			# 1-owner_key, 2-updated_time, 3-expiration, 4-site_key, 5-owner_key, 6-expiration
			@update_array = ($form_hash{'Owner'},time(),$epoch_exp,$site_key,$form_hash{'Owner'},$epoch_exp); 
			push(@dbi_updates,\@update_array);
			
			# 3. update topic LastUpdate
			$temp_meta->putKeyed( 'FIELD', {'name'=>"LastUpdate",'title'=>"LastUpdate",'value'=>time()});
			push(@meta_list,$temp_meta);
			
			# check if the owner changed
			my $temp_ok = $owner_key;
			$temp_ok =~ s/-//gi;
			if($temp_ok ne $form_hash{'Owner'}){
				push(@updated_sites,$site_key);
			}
			
		}
		elsif($topic_key){
			# topic exists, but no si row (this situation is highly unlikely)
			# 1. load topic 
			my $crap002 = $topic_handler->_convert_WT_Topics_out($topic_key);
			($temp_web,$temp_topic) = ($crap002->[0],$crap002->[1]);
			#($temp_web,$temp_topic) = $topic_handler->_convert_WT_Topics_out($topic_key);
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
			# 2. update topic with LastUpdate
			# 3. insert si row 
		}
		elsif($owner_key){
			# no topic, but si row exists (this situation is highly unlikely, only occurs if the topic is moved)
			# 1. load template
			my $accTemplate_key = Foswiki::Func::getPreferencesValue('PRODUCTSITETEMPLATE',$web);
			my $crap003 = $topic_handler->_convert_WT_Topics_out($accTemplate_key);
			($temp_web,$temp_topic) = ($crap003->[0],$crap003->[1]);
			#($temp_web,$temp_topic) = $topic_handler->_convert_WT_Topics_out($accTemplate_key);
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
			# 2. save new topic	
		}
		else{ 
			# no topic, and no si row
			# 1. load template (contains default owner_key and default expiration date)
			my $accTemplate_key = Foswiki::Func::getPreferencesValue('PRODUCTSITETEMPLATE',$web);
			my $crap004 = $topic_handler->_convert_WT_Topics_out($accTemplate_key);
			($temp_web,$temp_topic) = ($crap004->[0],$crap004->[1]);
			#($temp_web,$temp_topic) = $topic_handler->_convert_WT_Topics_out($accTemplate_key);
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
			@Fields = $temp_meta->find( 'FIELD' );
			foreach my $xf (@Fields){
				$form_hash{$xf->{'name'}} = $xf->{'value'};
			}
			# .....insert fields.....
			#$temp_meta->putKeyed( 'FIELD', {'name'=>"Owner",'title'=>"Owner",'value'=>$clean_owner_key}); already in Template Topic
			$temp_meta->putKeyed( 'FIELD', {'name'=>"SiteURL",'title'=>"SiteURL",'value'=>$site_name});
			#$temp_meta->putKeyed( 'FIELD', {'name'=>"Expiration",'title'=>"Expiration",'value'=>""}); already in Template Topic
			$temp_meta->putKeyed( 'FIELD', {'name'=>"LastUpdate",'title'=>"LastUpdate",'value'=>time()});
			# get the owner key
			$clean_owner_key = $form_hash{'Owner'}; # still has hyphens missing
			$owner_key = $clean_owner_key;
			# 2. save new topic
			$temp_meta->topic($clean_site_key);
			push(@meta_list,$temp_meta);
			# 3. insert si row
			@insert_array = ($site_key,$owner_key,time(),time()+60*60*24*30*3); # 3 months + 
			push(@dbi_inserts,\@insert_array);
		}
	}
	# edit DiD Inventory, incase the owner of the site changed
	# 		we want to point the number back to the user, instead of the site
	my $DiDupdateStatement = qq/UPDATE $did1 SET user_key=owner_key, site_key=NULL  
								WHERE site_key = ? ;/; # 1-site_key
	my $DiDupdateHandler = $topic_handler->database_connection()->prepare($DiDupdateStatement);
	
	
	# run the SQL from above in one shot
	my %opts01;
	$opts01{'nocommit'} = 1;
	eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();
		
		
		foreach my $xmeta (@meta_list){
			$xmeta->save(%opts01);
		}		
		foreach my $single_dbi_insert (@dbi_inserts){
			$insertHandler->execute(@{$single_dbi_insert});
		}
		foreach my $single_dbi_update (@dbi_updates){
			$updateHandler->execute(@{$single_dbi_update});
		}
		
		foreach my $did_update (@updated_sites){
			$DiDupdateHandler->execute($did_update);
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

# from '2011-10-04' to 132566494165165 epoch time
sub date_convert {
	my $date_string = shift;
	return undef unless $date_string;
	require Foswiki::Time;
	my $post_epoch = Foswiki::Time::parseTime($date_string);
	# after converting to epoch seconds
	return $post_epoch;

}
# site listing plugin
sub site_search {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins;
	my $session = $Foswiki::Plugins::SESSION;
	require Foswiki::Func;
	my $field = Foswiki::Func::extractNameValuePair( $args, 'Field' );
	my $user_key = $session->{user};

	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();

	my $si1 = $topic_handler->getTableName('Site_Inventory');
	my $Sites = $topic_handler->getTableName('Sites');
	my $selectStatement = qq/SELECT 
  si1.timestamp_epoch,   si1.finish,  s1.current_site_name
FROM 
  $si1 si1 INNER JOIN $Sites s1 ON si1.site_key = s1."key"
WHERE
  si1.owner_key = ? AND s1.current_site_name != 'e-flamingo.net';/; # 1-owner_key (don't include e-flamingo.net)
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($user_key);
	my ($last_update,$exp_date,$site_name);
	$selectHandler->bind_col( 1, \$last_update );
	$selectHandler->bind_col( 2, \$exp_date );
	$selectHandler->bind_col( 3, \$site_name );
	my @rows;
	while ($selectHandler->fetch) {
		# returns ($last_update,$exp_date,$site_name)
		push(@rows,_format_row($last_update,$exp_date,$site_name));
	}
	
	return join("\n",@rows)."\n";
}

sub _format_row {
	my ($last_update,$exp_date,$site_name) = @_;
	
	my @cells;
	require Foswiki::Func;
	push(@cells,' [[http://'.$site_name.']['.$site_name.']]');
	#push(@cells,' '.Foswiki::Func::formatTime($last_update,'$year-$mo-$day').' ') if $last_update;
	push(@cells,' '.Foswiki::Func::formatTime($exp_date,'$year-$mo-$day').' ') if $exp_date;
	#push(@cells,' ') unless $last_update;
	push(@cells,' ') unless $exp_date;

	return '|'.join('|',@cells).'|';
}

my $New_Site;
##########################################################################
=pod
---+ create_site ($product_meta,$order)
 this creates a site, where by the owner of the new site gets immediate access 
The function is ONLY called from the order_withdrawal function in the Orders Module
=cut
sub create_site {
	my $session = shift;
	my ($product_meta,$order_obj_old) = (shift,shift);
	my $request = $session->{request};
	my $web   = $product_meta->web;
	my $topic = $product_meta->topic;
	my $user_key = $session->{user};


	my $SiteName = $request->param('site_name');
	
	require Foswiki::Time;
	my $current_time = time();
	# get the db handler
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $Sites = $topic_handler->getTableName('Sites');
	my $SH = $topic_handler->getTableName('Site_History');
	my $Webs = $topic_handler->getTableName('Webs');
	my $WH = $topic_handler->getTableName('Web_History');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	my $UH = $topic_handler->getTableName('User_History');
	my $Groups = $topic_handler->getTableName('Groups');
	my $GH = $topic_handler->getTableName('Group_History');
	my $SI01 = $topic_handler->getTableName('Site_Inventory');
	my $did1 = $topic_handler->getTableName('DiD_Inventory');
	
	# get the order information
	my $order_key = $order_obj_old->key;
	# load a new order object (kind of a waste, but the code is cleaner?)
	require Foswiki::Plugins::AccountsPlugin::Orders;
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders->load($topic_handler,$order_key);

	
	my $owner_key = $order_obj->contract->owner;

	# get the owner's login name and email address
	bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my $owner_uh_row = $topic_handler->loadUHRowByUserKey($owner_key);
	($New_Site->{_owner_login},$New_Site->{_owner_email}) = ($owner_uh_row->{login_name},$owner_uh_row->{email});
	
	bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	# get the url information
	$New_Site->{_site_name} = $SiteName;
	
	# start creating the keys
	require File::Basename;
	require File::Find;
	my (%webs,%topics,%users,%groups);
	my $site_key = $topic_handler->createUUID();
	$New_Site->{_site_key} = $site_key;

	# fill up 
	my $COPYStatement = qq/SELECT web_name, topic_name, topic_content FROM foswiki."Example_Topics";/;
	my $COPYHandler = $topic_handler->database_connection()->prepare($COPYStatement);
	$COPYHandler->execute();
	my ($temp_tn,$temp_wn,$temp_tc);
	$COPYHandler->bind_col( 1, \$temp_wn );
	$COPYHandler->bind_col( 2, \$temp_tn );
	$COPYHandler->bind_col( 3, \$temp_tc );
	while ($COPYHandler->fetch) {
		_scoop_into_NEW_SITE($temp_wn,$temp_tn,$temp_tc);	
	}

	my $handler_hash;
	$handler_hash->{handler} = $topic_handler;
	# create site_handler
	my $Sites_insert_statement = qq/INSERT INTO $Sites ("key", link_to_latest, current_site_name, local_preferences, default_preferences,
		site_home,admin_user,admin_group,system_web,trash_web,home_web,guest_user )
			 VALUES (?,?,?,?,?,?,?,?,?,?,?,?)/;
	my $SH_insert_statement = qq/INSERT INTO $SH ("key", site_key, site_name, timestamp_epoch, user_key) VALUES (?,?,?,?,?)/;
	$handler_hash->{Site_Handler} = $topic_handler->database_connection()->prepare($Sites_insert_statement);
	$handler_hash->{SH_Handler} = $topic_handler->database_connection()->prepare($SH_insert_statement);

	# create a web_handler
	my $Webs_insert_statement = qq/INSERT INTO $Webs ("key", link_to_latest, current_web_name, site_key, web_preferences, web_home) VALUES (?,?,?,?,?,?)/;
	my $WH_insert_statement = qq/INSERT INTO $WH ("key", web_key, timestamp_epoch, user_key, web_name) VALUES (?,?,?,?,?)/;
	$handler_hash->{Webs_Handler} = $topic_handler->database_connection()->prepare($Webs_insert_statement);
	$handler_hash->{WH_Handler} = $topic_handler->database_connection()->prepare($WH_insert_statement);	
	# create a topic_handler
	my $Topics_insert_statement = qq/INSERT INTO $Topics ("key", link_to_latest, current_web_key, current_topic_name) VALUES (?,?,?,?)/;
	my $TH_insert_statement = qq/INSERT INTO $TH ("key", topic_key, user_key,web_key,timestamp_epoch,topic_name,topic_content,revision) VALUES (?,?,?,?,?,?,?,?)/;	
	$handler_hash->{Topics_Handler} = $topic_handler->database_connection()->prepare($Topics_insert_statement);
	$handler_hash->{TH_Handler} = $topic_handler->database_connection()->prepare($TH_insert_statement);
	# create user_handler
	my $Users_insert_statement = qq/INSERT INTO $Users ("key", link_to_latest, current_login_name, user_topic_key,site_key) VALUES (?,?,?,?,?)/;
	my $UH_insert_statement = qq/INSERT INTO $UH ("key",login_name, "password",user_key,change_user_key,timestamp_epoch, email) VALUES (?,?,?,?,?,?,?)/;
	$handler_hash->{Users_Handler} = $topic_handler->database_connection()->prepare($Users_insert_statement);
	$handler_hash->{UH_Handler} = $topic_handler->database_connection()->prepare($UH_insert_statement);	
	# create group_handler
	my $Groups_insert_statement = qq/INSERT INTO $Groups ("key", link_to_latest, group_topic_key, site_key) VALUES (?,?,?,?)/;
	my $GH_insert_statement = qq/INSERT INTO $GH ("key", user_key,timestamp_epoch,group_key) VALUES (?,?,?,?)/;
	$handler_hash->{Groups_Handler} = $topic_handler->database_connection()->prepare($Groups_insert_statement);
	$handler_hash->{GH_Handler} = $topic_handler->database_connection()->prepare($GH_insert_statement);

	# go through each topic and load it into the transaction
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;
	eval{
		
		$topic_handler->set_to_deferred();
		# get site information
		my $site_key = $New_Site->{_site_key};
		_site_input($handler_hash);
		# cycle through webs
		my %web_list = %{$New_Site};
		foreach my $web01 (keys %web_list){
			next if $web01 eq '_site_key';
			next if $web01 eq '_owner_login';
			next if $web01 eq '_owner_email';
			next if $web01 eq '_site_name';
			$New_Site->{$web01}->{_web_key};
			_web_input($handler_hash,$web01);
			
			my %topic_list = %{$New_Site->{$web01}};
			foreach my $topic01 (keys %topic_list){
				next if $topic01 eq '_web_key';
				if($topic01 =~ m/\s+/){
					# make sure topic01 is not just spaces
					next;
				}
				next unless $New_Site->{$web01}->{$topic01}->{_topic_key} && $New_Site->{$web01}->{$topic01}->{_topic_content};
				_topic_input($handler_hash,$web01,$topic01);
			}
		}
		# make sure the order is filled here
		$order_obj->fill_date($current_time);
		$order_obj->contract->start($current_time);
		$order_obj->save(); # (functional equivalent to saving)
		

		# do this inside of transaction
		_add_new_site_to_inventory($site_key,$owner_key,$topic_handler);

		$topic_handler->database_connection()->commit;
	};
	if ($@) {
		die "Rollback - failed to save ($site_key,$order_key) for reason:\n $@";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}
	# Do redirects on the Order Page

	#my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', 'Main', 'OrderFilling' ) );
	#$session->redirect($redirecturl);
}

sub _web_input {
	my ($handler_hash,$web_name) = @_;
	
	my $wh_row;
	
	$wh_row->{web_key} = $New_Site->{$web_name}->{_web_key};
	$wh_row->{timestamp_epoch} = time();
	$wh_row->{user_key} = $New_Site->{'Main'}->{'AdminUser'}->{_topic_key};
	$wh_row->{web_name} = $web_name;
	require Digest::SHA1;
	$wh_row->{key} = substr(Digest::SHA1::sha1_hex( $wh_row->{web_key}, $wh_row->{timestamp_epoch}, $wh_row->{user_key},$wh_row->{site_key}), 0, - 8);
	$handler_hash->{WH_Handler}->execute($wh_row->{key},$wh_row->{web_key},$wh_row->{timestamp_epoch},$wh_row->{user_key},$wh_row->{web_name});	

	my $web_row;
	$web_row->{key} = $wh_row->{web_key};
	$web_row->{link_to_latest} = $wh_row->{key};
	$web_row->{current_web_name} = $wh_row->{web_name};
	$web_row->{site_key} = $New_Site->{_site_key};
	$web_row->{web_preferences} = $New_Site->{$web_name}->{'WebPreferences'}->{_topic_key};
	$web_row->{web_home} = $New_Site->{$web_name}->{'WebHome'}->{_topic_key};
	$handler_hash->{Webs_Handler}->execute($web_row->{key},$web_row->{link_to_latest},$web_row->{current_web_name},$web_row->{site_key},$web_row->{web_preferences},
		$web_row->{web_home});	
	
}

sub _site_input {
	my ($handler_hash) = @_;

	my $sh_row;
	$sh_row->{site_key} = $New_Site->{_site_key};
	$sh_row->{site_name} = $New_Site->{_site_name};
	$sh_row->{timestamp_epoch} = time();
	$sh_row->{user_key} = $New_Site->{'Main'}->{'AdminUser'}->{_topic_key};
	my $crap = join(',',$sh_row->{site_name}, $sh_row->{timestamp_epoch}, $sh_row->{user_key},$sh_row->{site_key});

	# sha1( 1-site_name, 2-timestamp_epoch, 3-user_key, 4-site_key)
	require Digest::SHA1;
	$sh_row->{key} = substr(Digest::SHA1::sha1_hex( $sh_row->{site_name}, $sh_row->{timestamp_epoch}, $sh_row->{user_key},$sh_row->{site_key}), 0, - 8);
	$handler_hash->{SH_Handler}->execute($sh_row->{key},$sh_row->{site_key},$sh_row->{site_name},$sh_row->{timestamp_epoch},$sh_row->{user_key});
	my $site_row;
	$site_row->{key} = $sh_row->{site_key};
	$site_row->{link_to_latest} = $sh_row->{key};
	$site_row->{current_site_name} = $sh_row->{site_name};
	$site_row->{local_preferences} = $New_Site->{'Main'}->{'SitePreferences'}->{_topic_key};
	$site_row->{default_preferences} = $New_Site->{'System'}->{'DefaultPreferences'}->{_topic_key};
	$site_row->{site_home} = $New_Site->{'Main'}->{'WebHome'}->{_topic_key};
	$site_row->{admin_user} = $New_Site->{'Main'}->{'AdminUser'}->{_topic_key};
	$site_row->{admin_group} = $New_Site->{'Main'}->{'AdminGroup'}->{_topic_key};
	$site_row->{system_web} = $New_Site->{'System'}->{_web_key};
	$site_row->{trash_web} = $New_Site->{'Trash'}->{_web_key};
	$site_row->{home_web} = $New_Site->{'Main'}->{_web_key};
	$site_row->{guest_user} = $New_Site->{'Main'}->{'WikiGuest'}->{_topic_key};	
	$handler_hash->{Site_Handler}->execute($site_row->{key},$site_row->{link_to_latest} ,$site_row->{current_site_name} ,$site_row->{local_preferences} ,
		$site_row->{default_preferences} ,$site_row->{site_home}, 
		$site_row->{admin_user} ,$site_row->{admin_group} ,$site_row->{system_web} ,$site_row->{trash_web} ,$site_row->{home_web} ,$site_row->{guest_user} );	
}

sub _topic_input {
	my ($handler_hash,$web_name,$topic_name) = @_;
	my $TopicsHandler = $handler_hash->{Topics_Handler};
	my $THHandler = $handler_hash->{TH_Handler};
	my $topic_key = $New_Site->{$web_name}->{$topic_name}->{_topic_key};
	
	my $name_key = $handler_hash->{handler}->insert_Blob_Store($topic_name);
	my $content_key = $handler_hash->{handler}->insert_Blob_Store($New_Site->{$web_name}->{$topic_name}->{_topic_content}.' ');
	
	my $content = $New_Site->{$web_name}->{$topic_name}->{_topic_content};
	die "($web_name,$topic_name)\n----------\n$content\n-------------\n" unless $name_key && $content_key;
	#my $Topics_insert_statement = qq/INSERT INTO $Topics ("key", link_to_latest, current_web_key, current_topic_name) VALUES (?,?,?,?)/;
	#my $TH_insert_statement = qq/INSERT INTO $TH ("key", topic_key, user_key,revision,web_key,timestamp_epoch,topic_content,topic_name) VALUES (?,?,?,?,?,?,?,?)/;		
	my $th_row;
	$th_row->{topic_key} = $topic_key;
	$th_row->{user_key} = $New_Site->{'Main'}->{'AdminUser'}->{_topic_key};
	$th_row->{revision} = 1;
	$th_row->{web_key} = $New_Site->{$web_name}->{_web_key};
	$th_row->{timestamp_epoch} = time();
	$th_row->{topic_content_key} = $content_key;
	$th_row->{topic_name_key} = $name_key;
	$th_row->{key} = $handler_hash->{handler}->_createTHkey($th_row);
	$handler_hash->{TH_Handler}->bind_param( 1, $th_row->{key} ); 
	$handler_hash->{TH_Handler}->bind_param( 2, $th_row->{topic_key}); 
	$handler_hash->{TH_Handler}->bind_param( 3, $th_row->{user_key});
	$handler_hash->{TH_Handler}->bind_param( 4, $th_row->{web_key});
	$handler_hash->{TH_Handler}->bind_param( 5, $th_row->{timestamp_epoch});
	$handler_hash->{TH_Handler}->bind_param( 6, $th_row->{topic_name_key},{ pg_type => DBD::Pg::PG_BYTEA });
	$handler_hash->{TH_Handler}->bind_param( 7, $th_row->{topic_content_key},{ pg_type => DBD::Pg::PG_BYTEA });
	$handler_hash->{TH_Handler}->bind_param( 8, $th_row->{revision});  # this is to calculate the version number
	$handler_hash->{TH_Handler}->execute;
		
	my $topic_row;
	$topic_row->{key} = $topic_key;
	$topic_row->{link_to_latest} = $th_row->{key};
	$topic_row->{current_web_key} = $th_row->{web_key};
	$topic_row->{current_topic_name} = $th_row->{topic_name_key};
	$handler_hash->{Topics_Handler}->bind_param( 1, $topic_row->{key});
	$handler_hash->{Topics_Handler}->bind_param( 2, $topic_row->{link_to_latest});
	$handler_hash->{Topics_Handler}->bind_param( 3, $topic_row->{current_web_key});
	$handler_hash->{Topics_Handler}->bind_param( 4, $topic_row->{current_topic_name},{ pg_type => DBD::Pg::PG_BYTEA });
	$handler_hash->{Topics_Handler}->execute;
	
	# record that this topic has been inserted into the db
	$New_Site->{$web_name}->{$topic_name}->{_scooped} = 1;
	
	# check if it is a user
	_user_insert($handler_hash,$web_name,$topic_name);
	# check if it is a group
	_group_insert($handler_hash,$web_name,$topic_name);
	
}

sub _user_insert {
	my ($handler_hash,$web_name,$topic_name) = @_;
	# only two users Main.AdminUser and Main.WikiGuest
	my $bool = 0;
	$bool = 1 if $web_name eq 'Main' && $topic_name eq 'AdminUser';
	$bool = 1 if $web_name eq 'Main' && $topic_name eq 'WikiGuest';
	return undef unless $bool;
	my $uh_row;
	my $login_name;
	$login_name = $New_Site->{_owner_login} if $topic_name eq 'AdminUser';
	my $email01 = $New_Site->{_owner_email} if $topic_name eq 'AdminUser';
	$login_name = 'guest' if $topic_name eq 'WikiGuest';
	
	$uh_row->{login_name} = $login_name;
	$uh_row->{email} = $email01;
	$uh_row->{password} = 'no password';
	$uh_row->{user_key} = $New_Site->{$web_name}->{$topic_name}->{_topic_key};
	$uh_row->{change_user_key} = $New_Site->{'Main'}->{'AdminUser'}->{_topic_key};
	$uh_row->{timestamp_epoch} = time();
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	bless $handler_hash->{handler}, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
	$uh_row->{key} = $handler_hash->{handler}->_createUHkey($uh_row);
	bless $handler_hash->{handler}, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$handler_hash->{UH_Handler}->execute($uh_row->{key},$uh_row->{login_name},$uh_row->{password},$uh_row->{user_key},$uh_row->{change_user_key},$uh_row->{timestamp_epoch},$uh_row->{email});
 	
	my $user_row;
	$user_row->{key} = $uh_row->{user_key};
	$user_row->{link_to_latest} = $uh_row->{key};
	$user_row->{current_login_name} = $uh_row->{login_name};
	$user_row->{user_topic_key} = $uh_row->{user_key};
	$user_row->{site_key} = $New_Site->{_site_key};
	$handler_hash->{Users_Handler}->execute($user_row->{key},$user_row->{link_to_latest},$user_row->{current_login_name},$user_row->{user_topic_key},$user_row->{site_key});
	
	return 1;
}

sub _group_insert {
	my ($handler_hash,$web_name,$topic_name) = @_;
	# only one group Main.AdminGroup
	return undef unless $web_name eq 'Main' && $topic_name eq 'AdminGroup';
	my $gh_row;

	$gh_row->{user_key} = $New_Site->{'Main'}->{'AdminUser'}->{_topic_key};
	$gh_row->{group_key} = $New_Site->{$web_name}->{$topic_name}->{_topic_key};
	$gh_row->{timestamp_epoch} = time();
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	bless $handler_hash->{handler}, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
	$gh_row->{key} = $handler_hash->{handler}->_createGHkey($gh_row);
	bless $handler_hash->{handler}, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$handler_hash->{GH_Handler}->execute($gh_row->{key},$gh_row->{user_key},$gh_row->{timestamp_epoch},$gh_row->{group_key});
 	
	my $group_row;
	$group_row->{key} = $gh_row->{group_key};
	$group_row->{link_to_latest} = $gh_row->{key};
	$group_row->{group_topic_key} = $gh_row->{group_key};
	$group_row->{site_key} = $New_Site->{_site_key};
	$handler_hash->{Groups_Handler}->execute($group_row->{key},$group_row->{link_to_latest},$group_row->{group_topic_key},$group_row->{site_key});	
	
	return 1;
}

sub _site_insert {
	my ($handler_hash,$web_name,$topic_name) = @_;
	
}

sub _scoop_into_NEW_SITE{
	my ($web_name,$topic_name,$content) = @_;
    	
	# put keys into the new hash
	$New_Site->{$web_name}->{$topic_name}->{_topic_key} = Foswiki::Contrib::DBIStoreContrib::Handler::generateUUID() 
				unless $New_Site->{$web_name}->{$topic_name}->{_topic_key} && $web_name && $topic_name;
	$New_Site->{$web_name}->{_web_key} = Foswiki::Contrib::DBIStoreContrib::Handler::generateUUID()
				unless $New_Site->{$web_name}->{_web_key} && $web_name;
	$New_Site->{_site_key} = Foswiki::Contrib::DBIStoreContrib::Handler::generateUUID()
				unless $New_Site->{_site_key};
	$New_Site->{$web_name}->{$topic_name}->{_topic_content} = $content;

}

=pod
---+ add_new_site_to_inventory()
This is called from the Site_Inventory function
=cut

sub _add_new_site_to_inventory{
	my ($site_key,$owner_key,$topic_handler) = @_;
	my $session = $Foswiki::Plugins::SESSION;



	my $SiteInventory = $topic_handler->getTableName('Site_Inventory');
	my $insertStatement = qq/INSERT INTO $SiteInventory (site_key,owner_key,topic_key,timestamp_epoch) VALUES (?,?,?,?)/;

	# We need to create a $topic_key to put in the Site_Inventory Table
	my $new_topic_key = $topic_handler->createUUID();
	
	# Insert this row will not work unless foreign constraints are deferred
	# the topic page corresponding to this Site must have been already created
	my $insertHandler = $topic_handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($site_key,$owner_key,$new_topic_key,time());

	# we need to strip the dashes out since $site_key is a UUID
	my $clean_site_key = $site_key;
	$clean_site_key =~ s/-//i;
	# we need to also create a topic corresponding to this Site
	# create order invoice page from an invoice template topic
	my $site_topic = Foswiki::Meta::->new($session,'Sites'.$clean_site_key);
	$site_topic->web('Main');
	$site_topic->topic('Sites9ed37a7a44244be7a5b69772a3e6a615');
	$site_topic->load();
	# set the info for the new Site Inventory Topic Page
	$site_topic->web('Main');
	$site_topic->topic('Sites'.$clean_site_key);
	my $site_text = qq/---+!! Site \n\n/;
	$site_topic->text($site_text);

	# save without commiting
	# set nocommit and preseed_topic_key options for DBIStoreContrib save
	my %opts;
	$opts{'nocommit'} = 1;
	$opts{'preseed_topic_key'} = $new_topic_key;
	$opts{'handler'} = $topic_handler;
	# save	

	$site_topic->save(%opts);

	return $new_topic_key;	
}

##########################################################################
=pod
---+ activate_site
needs to be run after create_site, loads up derivative tables of topic_history 
=cut
sub activate_site {
	my $session = shift;

	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Webs = $topic_handler->getTableName('Webs');
	my $Topics = $topic_handler->getTableName('Topics');
	my $BS = $topic_handler->getTableName('Blob_Store');

	# the web name will be the site_key
	my $selectStatement = qq/SELECT 
  s1."key", 
  s1.product_id, 
  w1.current_web_name, 
  tname."value"
FROM 
  $Webs w1
	INNER JOIN $Topics t1 ON t1.current_web_key = w1."key"
	INNER JOIN $Sites s1 ON w1.site_key = s1."key",
  $BS tname
WHERE 
  tname."key" = t1.current_topic_name AND
  s1."key" = ? ; /; # 1-site_key
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($site_key);
	my ($key,$product_id,$web_name,$topic_name);
	$selectHandler->bind_col( 1, \$key );
	$selectHandler->bind_col( 2, \$product_id );
	$selectHandler->bind_col( 3, \$web_name );
	$selectHandler->bind_col( 4, \$topic_name );
	require Foswiki::Func;
	# do priority saves first
	my $MainP = {'SitePreferences' => 1,'WebPreferences' => 1,'ResetPassword' => 1};
	my $TrashP = {'WebPreferences' => 1};
	my $SystemP = {'DefaultPreferencesForm' => 1,'DefaultPreferences' => 1,'WebPreferences' => 1,'FAQForm' => 1,'PhoneDialPlanTable'};
	my ($temp_meta,$temp_text);
	foreach my $t01 (keys %$SystemP){
		# load each topic and save it again	
		($temp_meta,$temp_text) = Foswiki::Func::readTopic('System',$t01);
		# load the text into the copy table
		$temp_meta->save;	
	}
	foreach my $t01 (keys %$MainP){
		# load each topic and save it again	
		($temp_meta,$temp_text) = Foswiki::Func::readTopic('Main',$t01);
		# load the text into the copy table
		$temp_meta->save;	
	}	
	foreach my $t01 (keys %$TrashP){
		# load each topic and save it again	
		($temp_meta,$temp_text) = Foswiki::Func::readTopic('Trash',$t01);
		# load the text into the copy table
		$temp_meta->save;	
	}
	
	eval{
		while ($selectHandler->fetch) {
			# if product id already exists, then exit
			return undef if $product_id;
			# make sure that there is a site that corresponds to the key
			return undef unless $key;
			# load each topic and save it again	
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($web_name,$topic_name);
			# load the text into the copy table
			$temp_meta->save;
		}
		
	};
	if ($@) {
		die "Rollback - failed to save ($web_name,$topic_name) for reason:\n $@";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}

}

##########################################################################
=pod
---+ copy_site
used to cache site pages to be used by create_site 
=cut
sub copy_site {
	my $session = shift;
	
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Webs = $topic_handler->getTableName('Webs');
	my $Topics = $topic_handler->getTableName('Topics');
	my $BS = $topic_handler->getTableName('Blob_Store');

	# the web name will be the site_key
	my $selectStatement = qq/SELECT 
  s1."key", 
  s1.product_id, 
  w1.current_web_name, 
  tname."value"
FROM 
  $Webs w1
	INNER JOIN $Topics t1 ON t1.current_web_key = w1."key"
	INNER JOIN $Sites s1 ON w1.site_key = s1."key",
  $BS tname
WHERE 
  tname."key" = t1.current_topic_name AND
  s1."key" = ? ; /; # 1-site_key
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($site_key);
	my ($key,$product_id,$web_name,$topic_name);
	$selectHandler->bind_col( 1, \$key );
	$selectHandler->bind_col( 2, \$product_id );
	$selectHandler->bind_col( 3, \$web_name );
	$selectHandler->bind_col( 4, \$topic_name );
	
	
	my $insertStatement = qq/INSERT INTO foswiki."Example_Topics" (web_name, topic_name, topic_content) VALUES (?,?,?);/;
	my $insertHandler = $topic_handler->database_connection()->prepare($insertStatement);
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;
	require Foswiki::Func;
	eval{


	while ($selectHandler->fetch) {
		# if product id already exists, then exit
		#return undef if $product_id;
		# make sure that there is a site that corresponds to the key
		return undef unless $key;
		
		# load each topic and save it again	
		my ($temp_meta,$temp_text) = Foswiki::Func::readTopic($web_name,$topic_name);
		# load the text into the copy table
		$insertHandler->execute($web_name,$topic_name,$temp_text);
		#$temp_meta->save;
		
	}
		$topic_handler->database_connection()->commit;
	};
	if ($@) {
		die "Rollback - failed to save ($web_name,$topic_name) for reason:\n $@";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}

}
##########################################################################
=pod
---+ site_man_hours
done by admin, creates and updates invoices
=cut
# site_man_hours($handler,$site_name,$start_time,$end_time)-> 1 person * 1 month
sub site_man_hours {
	my ($inWeb,$inTopic, $args) = @_;

	my ($site_name,$start_time,$end_time);
	require Foswiki::Func;
	my $site_name = Foswiki::Func::extractNameValuePair( $args, 'site' );
	my $start_time = Foswiki::Func::extractNameValuePair( $args, 'startdate' );
	my $end_time = Foswiki::Func::extractNameValuePair( $args, 'enddate' );	

	require Foswiki::Time;
	# change start_time to epoch time
	my $start_epoch = Foswiki::Time::parseTime($start_time,1) if $start_time;
	$start_epoch = 0 unless $start_epoch;
	# change end_time to epoch time
	my $end_epoch = Foswiki::Time::parseTime($end_time,1);
	$end_epoch = time() unless $end_epoch;
	# we assume there are 60seconds*60minutes*24hours*30days in one month
	return site_man_seconds_actual($site_name,$start_epoch,$end_epoch)/60.0/60.0/24.0/30.0;
}

# site_man_seconds_actual($site_name,$start_epoch,$end_epoch)-> 1 person * 1 second
sub site_man_seconds_actual {
	my ($site_name,$start_epoch,$end_epoch) = @_;
	# load up the sql tables
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	
	my $selectStatement = qq^
SELECT ((SELECT 
  SUM(?+ -1*?)
FROM 
  $Users u2
   INNER JOIN $Sites s2 ON u2.site_key = s2."key"

WHERE 
 u2."key" != s2.guest_user AND s2.current_site_name = ?)
-
(SELECT SUM(manseconds) FROM (SELECT 
  (CASE WHEN thf.timestamp_epoch > ? THEN ?
				ELSE thf.timestamp_epoch
         END)+ -1*
         (CASE WHEN thi.timestamp_epoch < ? THEN ?
				ELSE thi.timestamp_epoch
         END) as manseconds
 FROM
  $TH thf
	INNER JOIN $TH thi ON thf.topic_key = thi.topic_key AND thf.revision = thi.revision + 1
	INNER JOIN (
  $Users u1
   INNER JOIN $Sites s1 ON u1.site_key = s1."key"
  ) ON thf.topic_key = u1.user_topic_key
WHERE 
   u1."key" != s1.guest_user AND s1.current_site_name = ? 
   AND thi.web_key = s1.trash_web
   AND thi.timestamp_epoch < ?
   AND thf.timestamp_epoch > ?
UNION
SELECT 0 as manseconds
) as mantable) )^; # 1-end_time,2-start_time,3-site_name,4-end_time,5-end_time,6-start_time,7-start_time,8-site_name,9-end_time,10-start_time
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($end_epoch,$start_epoch,$site_name,$end_epoch,$end_epoch,$start_epoch,$start_epoch,$site_name,$end_epoch,$start_epoch);
	my ($manseconds);
	$selectHandler->bind_col( 1, \$manseconds );
	while ($selectHandler->fetch) {
		return $manseconds if $manseconds > 0;
	}
	return 0;
}

##########################################################################
=pod
---+ all_site_man_seconds
done by admin, creates and updates invoices

The returned hash has the following format:
	site_key -> [owner_key,start_epoch,end_epoch,site_name]
=cut

sub all_site_man_seconds {
	my ($start_epoch,$end_epoch) = @_;
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $SiteInventory = $topic_handler->getTableName('Site_Inventory');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	
	# Fetch all of the sites in the Site_Inventory
	my $selectStatement = qq^
	SELECT si.site_key,si.owner_key,si.timestamp_epoch,si.finish,s1.current_site_name
	FROM $SiteInventory si INNER JOIN $Sites s1 ON si.site_key = s1."key"
	WHERE timestamp_epoch < ? AND s1.current_site_name != 'e-flamingo.net'
	^;	# 1-end_epoch
	
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($end_epoch);
	
	my ($site_key,$owner_key,$site_start_epoch,$site_end_epoch,$site_name);
	$selectHandler->bind_col( 1, \$site_key );
	$selectHandler->bind_col( 2, \$owner_key );
	$selectHandler->bind_col( 3, \$site_start_epoch );
	$selectHandler->bind_col( 4, \$site_end_epoch );
	$selectHandler->bind_col( 5, \$site_name );
	
	my $site_hash;
	while ($selectHandler->fetch) {
		$site_hash->{$site_key}->{'owner_key'} = $owner_key;
		$site_hash->{$site_key}->{'start_epoch'} = $site_start_epoch;
		$site_hash->{$site_key}->{'end_epoch'} = $site_end_epoch;
		$site_hash->{$site_key}->{'site_name'} = $site_name;
		push(@{$site_hash->{'users'}->{$owner_key}},$site_key);
	}
	
	# for each site, get site_man_seconds
	foreach my $s1_key (keys %{$site_hash}){
		# look in the above while loop to see why 'users' is needed
		next if $s1_key eq 'users';
		
		my ($start01,$end01) = ($start_epoch,$end_epoch);
		# if the site started after cost calculation period started, start from site time of inception
		if($site_hash->{$site_key}->{'start_epoch'} > $start_epoch){
			$start01 = $start_epoch;
		}
		# make sure that the site was not created after the cost calculation period
		if($site_hash->{$site_key}->{'start_epoch'} > $end_epoch){
			$start01 = undef;
		}	
		
		# only look up man_seconds if the site is owned by a user of e-flamingo.net in the cost calculation period
		$site_hash->{$s1_key}->{'man_seconds'} = site_man_seconds_actual($site_hash->{$s1_key}->{'site_name'},$start01,$end_epoch) if $start01;
	}
	return $site_hash;
} 


##########################################################################
=pod
---+ site_info
%SITEINFO{"site_name/owner" topic="site_topic"}%
=cut

sub site_info {
	my ($inWeb,$inTopic, $args) = @_;
	my $session = $Foswiki::Plugins::SESSION;
	
	# get the Order web,topic pair
	require Foswiki::Func;
	my $site_topic_WT = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	$site_topic_WT = $session->{webName}.'.'.$session->{topicName} unless $site_topic_WT;
	
	my $main_arg = Foswiki::Func::extractNameValuePair( $args );
	
	# get the order id
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	my $site_topic = $topic_handler->_convert_WT_Topics_in($site_topic_WT);
	
	return undef unless $site_topic;

	my $Sites = $topic_handler->getTableName('Sites');
	my $SiteInventory = $topic_handler->getTableName('Site_Inventory');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');
	my $Users = $topic_handler->getTableName('Users');
	# get the site info, load it into cache?
	my $selectStatement = qq/SELECT 
  s1."key",
  s1.current_site_name, 
  si1.owner_key,
  u1.user_topic_key
FROM 
  $SiteInventory si1
	INNER JOIN $Sites s1 ON s1."key" = si1.site_key
	INNER JOIN $Users u1 ON si1.owner_key = u1."key"
WHERE 
  si1.topic_key = ? ;/;
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($site_topic);
	my ($site_key,$current_site_name,$owner_key,$user_topic_key);
	$selectHandler->bind_col( 1, \$site_key );
	$selectHandler->bind_col( 2, \$current_site_name );
	$selectHandler->bind_col( 3, \$owner_key );
	$selectHandler->bind_col( 4, \$user_topic_key );
	
	while ($selectHandler->fetch) {
		my $temp_array_ref = $topic_handler->convert_Var('WT','Users',$owner_key,'out');
		my ($owner_web,$owner_topic) = ($temp_array_ref->[0],$temp_array_ref->[1]);
		$topic_handler->putMemcached('site_inventory',$current_site_name.'owner_key',$owner_key);
		$topic_handler->putMemcached('site_inventory',$current_site_name.'site_key',$site_key);
		$topic_handler->putMemcached('site_inventory',$current_site_name.'owner_WT',$owner_web.'.'.$owner_topic);
		return $owner_web.'.'.$owner_topic if $main_arg eq 'owner';
		return $current_site_name if $main_arg eq 'site_name';
	}
	return '';
}

1;
__END__
---+ Billing Per User
SELECT ceil(SUM(manhours)/60/60/24/30*100) FROM 
(
SELECT 
  SUM(thf.timestamp_epoch - thi.timestamp_epoch) as manhours
FROM 
  (foswiki."Topic_History" thf INNER JOIN foswiki."Topic_History" thi ON thf.topic_key = thi.topic_key AND thf.revision = thi.revision + 1)
 INNER JOIN
  ( foswiki."Users" u1 INNER JOIN foswiki."Sites" s1 ON s1."key" = u1.site_key )
	ON thi.topic_key = u1.user_topic_key
WHERE 
  s1.current_site_name = 'tokyo.e-flamingo.net' AND thi.web_key != s1.trash_web 
  
 -- AND thi.timestamp_epoch >= '1354287600' AND thf.timestamp_epoch <= '1356966000' AND u1.current_login_name = 'dejesus.joel';

 -- now '1334232935'

UNION

SELECT 
  '1334232935'-th.timestamp_epoch as manhours
FROM
  foswiki."Topic_History" th
INNER JOIN
    ( foswiki."Users" u2 INNER JOIN foswiki."Sites" s2 ON s2."key" = u2.site_key )
	ON th.topic_key = u2.user_topic_key
INNER JOIN
  foswiki."Topics" t1 ON th."key" = t1.link_to_latest
  
WHERE
  s2.current_site_name = 'tokyo.e-flamingo.net' AND th.web_key != s2.trash_web 
) AS manhour_table

---+ Update Site Inventory
SELECT 
  s1.current_site_name, 
  regexp_replace(s1."key"::text, '-', '','g') as site_key,
  t2."key" as topic_key,
  t2.link_to_latest as th_key
FROM 
  foswiki."Sites" s1 
    LEFT JOIN (foswiki."Topics" t2
		INNER JOIN (foswiki."Webs" w2 INNER JOIN foswiki."Sites" s2 ON w2.site_key = s2."key" AND s2.current_site_name = 'tokyo.e-flamingo.net')
			ON w2."key" = t2.current_web_key AND w2.current_web_name = 'Coverage')
		ON t2.current_topic_name = foswiki.sha1bytea(regexp_replace(s1."key"::text, '-', '','g'))
WHERE   s1.current_site_name != 'e-flamingo.net';



-- t1 topic_key, l2l, current_web_key, current_topic_name
-- th key, topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name
   
/*
   INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
      VALUES (topic_key, link_to_latest, web_key, topic_name_key);

   INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
      VALUES (link_to_latest, topic_key, user_key, revision, web_key, timestamp_epoch, topic_content_key, topic_name_key);
*/
-- sha1_hex( $th_row_ref->{topic_key}, $th_row_ref->{user_key}, $th_row_ref->{web_key}, $th_row_ref->{timestamp_epoch}, $th_row_ref->{topic_name_key}, $th_row_ref->{topic_content_key})
--foswiki.insert_newsite_topic(key0 uuid, link_to_latest0 uuid, current_web_key0 uuid, current_topic_name0 bytea, new_key0 uuid, 	th_key0 uuid, topic_key0 uuid, user_key0 uuid, revision0 integer, web_key0 uuid, timestamp_epoch0 integer, topic_content0 bytea, topic_name0 bytea)

--foswiki.insert_newsite_topic(key0 uuid, link_to_latest0 uuid, current_web_key0 uuid, current_topic_name0 bytea, new_key0 uuid, 	th_key0 uuid, topic_key0 uuid, user_key0 uuid, revision0 integer, web_key0 uuid, timestamp_epoch0 integer, topic_content0 bytea, topic_name0 bytea)
/*
    INSERT INTO foswiki."MetaPreferences_History" ("key","type","name","value",topic_history_key) VALUES (foswiki.sha1_uuid(foswiki.text2bytea(topic_history_key0::text||+name0||+value0)), 
	type0, value0, topic_history_key0) RETURNING "key" INTO retval;
*/
    
