package Foswiki::Plugins::AccountsPlugin::Orders;

use strict;
use Foswiki::UI::Accounts();
use POSIX qw( ceil );
use Foswiki::Plugins::AccountsPlugin();
use Foswiki::Plugins::AccountsPlugin::Contracts();
use Foswiki::Plugins::AccountsPlugin::Products();


############ Constructors #########################

####################################################################################################################
=pod
---+ place_order
Foswiki::Plugins::AccountsPlugin::Orders::->place_order({'product_type' => 'Credits', 'contract_topic'=> $contract_thkey, 
					'handler'=>$handler, 'owner' => $user_key, 'product_topic' => $product_thkey}) => creates order_obj
Use this function to create a new order
=cut
sub place_order {
	my $class = shift;
	my $input = shift;
	my $this = {};
	bless $this, $class;
	# set order_obj internal variables
	$this->product_type($input->{'product_type'});
	$this->product_topic($input->{'product_topic'});
	$this->fill_date(0);
	$this->handler($input->{'handler'});
	# set contract_obj internal variables
	# need to also create a contract key
	$this->contract(Foswiki::Plugins::AccountsPlugin::Contracts::->new());
	$this->contract->type($input->{'contract_topic'});
	$this->contract->handler($this->handler);
	$this->contract->owner($input->{'owner'});
	
	
	# mark this order object as representing a new order
	$this->_previously_loaded(0);
	$this->contract->_previously_loaded(0);
	
	return $this;
}
####################################################################################################################
=pod
---+ load($handler,$order_id)
Creates a new order object representing a previously existing order
=cut
sub load {
	# create the class object first
	my $class = shift;
	my $handler = shift;
	my $key = shift;

	my $this;
	$this->{key} = $key;	
	bless $this, $class;
	$this->key($key);
	$this->handler($handler);
	
	
	# load the order object first
	my $Order_Book = $handler->getTableName('Order_Book');
	my $Contracts = $handler->getTableName('Contracts');
	my $selectStatement = qq/SELECT 
  ob1.order_id, ob1.post_date, 
  ob1.fill_date, ob1.product_type, 
  c1.term, c1.start_date, 
  c1.end_date, c1.type_of_contract, 
  c1.owner_key, c1.contract_id
FROM 
  $Order_Book ob1 INNER JOIN $Contracts c1 ON ob1.contract_id = c1.contract_id
WHERE
  ob1.order_id = ? ;/; # 1-order_key
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	
	
	$selectHandler->execute($this->key);
	
	my ($order_id, $post_date, $fill_date, $product_type, $contract_id, $owner_key,$type_of_contract,$end_date ,$start_date,$term);
	$selectHandler->bind_col( 1, \$order_id );
	$selectHandler->bind_col( 2, \$post_date );
	$selectHandler->bind_col( 3, \$fill_date );
	$selectHandler->bind_col( 4, \$product_type );
	$selectHandler->bind_col( 5, \$term );
	$selectHandler->bind_col( 6, \$start_date );
	$selectHandler->bind_col( 7, \$end_date );
	$selectHandler->bind_col( 8, \$type_of_contract );
	$selectHandler->bind_col( 9, \$owner_key );
	$selectHandler->bind_col( 10, \$contract_id );
	while ($selectHandler->fetch) {
		# set order_obj internal variables
		$this->product_topic($product_type); #type vs topic is confusing, it is a topic_history_key
		$this->post_date($post_date);
		$this->fill_date($fill_date);
		# set contract_obj internal variables
		$this->contract(Foswiki::Plugins::AccountsPlugin::Contracts::->new($contract_id));
		$this->contract->term($term);
		$this->contract->start($start_date);
		$this->contract->end($end_date);
		$this->contract->type($type_of_contract);
		$this->contract->handler($this->handler);
		$this->contract->owner($owner_key);
		
		# Cache the info fetched into Memcached
		Foswiki::Plugins::AccountsPlugin::setOrder($this);
	}
	# get the invoice topic loaded up as well
	require Foswiki::Func;
	my ($ow,$ot) = Foswiki::Func::getWTFromTopicKey($order_id);
	my ($invoice_meta,$invoice_meta_text) = Foswiki::Func::readTopic($ow,$ot);
	$this->invoice_meta($invoice_meta);

	# mark this order object as representing an existing order
	if($order_id){
		$this->_previously_loaded(1);
		$this->contract->_previously_loaded(1);
	}
	else{
		#$this->_previously_loaded(0);
		#$this->contract->_previously_loaded(0);
		return undef;		
	}
	return $this;
}

####################################################################################################################
=pod
---+ new
creates an empty object.  Don't call this, just call $order->load to load an existing order
=cut
sub new {
	my $class = shift;
	my $key = shift;	
	my $this;
	$this->{key} = $key;
	bless $this, $class;
	return $this;
}


####################### Writers to Database #########################
####################################################################################################################
=pod
---+ save
There are 2 situations that must be covered, new orders and previous orders.

=cut

sub save {
	my $this = shift;
	my $crapper = $this->_previously_loaded;
	# find out if this is a new order, or old order
	if($this->_previously_loaded == 1){
		# this is an old order
		$this->update_order();
		
	}
	else{
		# this is a new order
		$this->save_new_order();
	}
}

# ($fill_date,$start_date)-> update Contracts and Order_Book with fill_date
# THIS UPDATES the db, so don't "order_obj->save"
sub save_new_order {
	my $this = shift;
	my $order_id = $this->handler->createUUID();
	$this->key($this->handler->createUUID());
	
	
	# save the contract
	$this->contract->save;


	# check for the db handler
	die "no handler" unless $this->handler;
	die "no contract key" unless $this->contract->key;

	# set nocommit and preseed_topic_key options for DBIStoreContrib save
	my %opts;
	$opts{'nocommit'} = 1;
	$opts{'preseed_topic_key'} = $this->key;
	$opts{'handler'} = $this->handler;

	$this->invoice_meta->save(%opts);

	
	$this->post_date(time());
	
	$this->fill_date('-1') unless $this->fill_date;
	
	my $Order_Book = $this->handler->getTableName('Order_Book');
	my $insertStatement = qq/
  INSERT INTO $Order_Book (order_id, contract_id, post_date, fill_date, product_type)
VALUES (?,?,?,?,?);
	/;
	my $insertHandler = $this->handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($this->key,$this->contract->key,$this->post_date,$this->fill_date,$this->product_topic);

	# blah
	return $this->key;
}

# ($fill_date,$start_date)-> update Contracts and Order_Book with fill_date
# THIS UPDATES the db, so don't "order_obj->save"
sub update_order {
	my $this = shift;
	my $handler = $this->handler;
	#my $fill_date = $this->fill_date;
	#my $new_start_date = $this->contract->start;
	
	#$new_start_date = $fill_date unless $new_start_date;
	
	# update the Order_Book
	my $Order_Book = $handler->getTableName('Order_Book');
	my $updateStatement = qq/
  UPDATE $Order_Book 
  SET fill_date = ?
  WHERE order_id = ? ;
	/;# 1-fill_date, 2-key
	my $updateHandler = $handler->database_connection()->prepare($updateStatement);	
	$updateHandler->execute($this->fill_date,$this->key);
	
	# update Contract Dates
	$this->contract->save();
	#$this->contract->update_dates($fill_date,$new_start_date);

	my %opts;
	$opts{'nocommit'} = 1;
	$opts{'handler'} = $this->handler;
	$this->invoice_meta->save(%opts);	
}

###########   variable setters and getters  ###########
sub key {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{key} = $x;
		return $this->{key};
	}
	else{
		return $this->{key};
	}
}

sub product_type {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{product_type} = $x;
		return $this->{product_type};
	}
	else{
		return $this->{product_type};
	}
}

# this is a topic_history_key
sub product_topic {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{product_topic} = $x;
		return $this->{product_topic};
	}
	else{
		return $this->{product_topic};
	}
}
# this is the Meta Object
sub invoice_meta {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{invoice_meta} = $x;
		return $this->{invoice_meta};
	}
	else{
		return $this->{invoice_meta};
	}
}
# used for loading the meta topic if there is not an already existing one
# this is used when placing orders
sub invoice_meta_load {
	my $this = shift;
	return undef if $this->invoice_meta;
	my $session = $Foswiki::Plugins::SESSION;
	my $handler = $this->handler;
	my $current_time = time();
	my ($web,$topic) = ('Main','OrderInvoiceTemplateView');
	require Foswiki::Meta;
	my $invoice_topic = Foswiki::Meta::->new($session,'Main','ConsumptionOrder'.$current_time);
	$invoice_topic->web('Main');
	$invoice_topic->topic('OrderInvoiceTemplateView');
	$invoice_topic->load();
	my ($i,$t_exists) = (0,1);

	# we auto increment the number in order to make the topic name of the Invoice Topic unique
	while(!$t_exists){
		my $throw01 = $handler->LoadTHRow($web,'ConsumptionOrder'.$current_time.'N'.$i);
		$t_exists = 0 unless $handler->fetchTopicKeyByWT($web,'ConsumptionOrder'.$current_time.'N'.$i);
		$i += 1;
		die "Overloop" if $i>100;
	}
	$invoice_topic->web($web);
	$invoice_topic->topic('ConsumptionOrder'.$current_time.'N'.$i);	
	$this->invoice_meta($invoice_topic);

}

	

# 0 for not filled, time epoch for filled
sub fill_date {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{fill_date} = $x;
		return $this->{fill_date};
	}
	else{
		return $this->{fill_date};
	}
}

# post date
sub post_date {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{post_date} = $x;
		return $this->{post_date};
	}
	else{
		return $this->{post_date};
	}
}
sub contract {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{contract} = $x;
		return $this->{contract};
	}
	else{
		return $this->{contract};
	}
}
# this is for handling databases
sub handler {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{handler} = $x;
		return $this->{handler};
	}
	else{
		return $this->{handler};
	}
}

# this is for marking whether this is a new order or a previously existing order
sub _previously_loaded {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{_previously_loaded} = $x;
		return $this->{_previously_loaded};
	}
	else{
		return $this->{_previously_loaded};
	}
}
#######################################################




#######################################################
# -----------------Rendering----------------------------
# %ORDER{"Post_Date" topic="Web.Topic"}% where WT-> topic_key = order_key
sub order_tag_renderer {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Func;
	my $topic_v = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	my ($ow1,$ot2) = Foswiki::Func::normalizeWebTopicName($inWeb,$topic_v);
	
	# 1. get the topic_key so that the order can be loaded
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	
	$handler->LoadTHRow($ow1,$ot2);
	my $order_key = $handler->fetchTopicKeyByWT($ow1,$ot2);
	
	# 2. load the order object via $order_key
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($handler,$order_key);
	return undef unless $order_obj;
	
	# get field Of Interest
	my $fieldOI = Foswiki::Func::extractNameValuePair($args);
	my $tag_return = $order_obj->_tag_mapper($fieldOI);
	return $tag_return;
}

# ('Fill_Date') -> cleanly formated
sub _tag_mapper {
	my $this = shift;
	my $tag = shift;
	my $handler = $this->handler;
	# for some unknown reason, we must rebless
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	
	my $return_value = "";
	if($tag eq 'Fill_Date'){
		require Foswiki::Time;
		# timezone is not defined
		$return_value = Foswiki::Time::formatTime($this->fill_date, '$rcs' );
		$return_value = "Unfilled" if $this->fill_date == 0;
	}
	elsif($tag eq 'Post_Date'){
		require Foswiki::Time;
		# timezone is not defined
		$return_value = Foswiki::Time::formatTime($this->post_date, '$rcs' );
	}
	elsif($tag eq 'Order_Age'){
		# defined in Hours
		$return_value = ceil((time()-$this->post_date)/3600);
		
	}
	elsif($tag eq 'Owner'){
		my $user_key = $this->contract->owner;
		my $crap001 = $handler->_convert_WT_Users_out($user_key);
		my ($u_w,$u_t) = ($crap001->[0],$crap001->[1]);
		#my ($u_w,$u_t) = $handler->_convert_WT_Users_out($user_key);
		$return_value = "$u_w.$u_t";
	}
	elsif($tag eq 'Product_Page'){
		my $th_key = $this->product_topic;
		# need to convert this to a page link
		my ($w1,$t1,$rev) = $handler->LoadWTRFromTHKey($th_key);
		my $wtpair01 = $w1.'.'.$t1;
		$return_value = "$wtpair01";
	}
	elsif($tag eq 'Product_Page_Version'){
		my $th_key = $this->product_topic;
		# need to convert this to a page link
		my ($w1,$t1,$rev) = $handler->LoadWTRFromTHKey($th_key);
		$return_value = "$rev";
	}
	elsif($tag eq 'Contract_Page'){
		my $th_key = $this->contract->type;
		# need to convert this to a page link
		my ($w1,$t1,$rev) = $handler->LoadWTRFromTHKey($th_key);
		my $wtpair01 = $w1.'.'.$t1;
		$return_value = "$wtpair01";
	}
	elsif($tag eq 'Contract_Page_Version'){
		my $th_key = $this->contract->type;
		# need to convert this to a page link
		my ($w1,$t1,$rev) = $handler->LoadWTRFromTHKey($th_key);
		$return_value = "$rev";
	}
	elsif($tag eq 'Term'){
		$return_value = $this->contract->term;
	}
	elsif($tag eq 'Start'){

		require Foswiki::Time;
		# timezone is not defined
		$return_value = Foswiki::Time::formatTime($this->contract->start, '$rcs' );
		$return_value = "N/A" unless $this->contract->start;
	}
	elsif($tag eq 'End'){

		require Foswiki::Time;
		# timezone is not defined
		$return_value = Foswiki::Time::formatTime($this->contract->end, '$rcs' );
		$return_value = "N/A" unless $this->contract->end;
	}
	elsif($tag eq 'Invoice'){
		my ($iw,$it) = $handler->LoadWTFromTopicKey($this->key);
		$return_value = "[[$iw.$it][$it]]";
	}
	return $return_value;
}

=pod
---+ Order Searches
%ORDERSEARCH{product="Web.Topic" fill_date="0" classification="0"}% where WT-> topic_key -> many th_key's
   * product: comma list of WT of products (multiple ok)
   * fill_date: less than value 
   * classification: credit, DiD, or site (only 1)
=cut
sub search_tag_renderer {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Func;
	my @prod_WT_list = split(',',Foswiki::Func::extractNameValuePair( $args, 'product' ));
	
	my $fill_date = Foswiki::Func::extractNameValuePair( $args, 'fill_date' ) || '0';
	my $classification = Foswiki::Func::extractNameValuePair( $args, 'classification' ) || '';
	# get the handler
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	# get product_topic_key
	my @product_key_list;
	foreach my $prod_WT (@prod_WT_list){
		$prod_WT = $handler->trim($prod_WT);
		my ($prod_w,$prod_t) =  Foswiki::Func::normalizeWebTopicName($inWeb,$prod_WT);
		$handler->LoadTHRow($prod_w,$prod_t);
		my $product_key = $handler->fetchTopicKeyByWT($prod_w,$prod_t);
		push(@product_key_list,$product_key);	
	}
	return undef unless scalar(@product_key_list) > 0;
	
	# do a search for all orders (basically, $order_obj->load multiple times)
	my $product_string = join("','",@product_key_list);
	$product_string = "'$product_string'";
	# 1. load the order object first
	my $TH = $handler->getTableName('Topic_History');
	my $Order_Book = $handler->getTableName('Order_Book');
	my $Contracts = $handler->getTableName('Contracts');
	my $selectStatement = qq/SELECT 
  ob1.order_id, ob1.post_date, 
  ob1.fill_date, ob1.product_type, 
  c1.term, c1.start_date, 
  c1.end_date, c1.type_of_contract, 
  c1.owner_key, c1.contract_id
FROM 
 $Order_Book ob1 
    INNER JOIN $Contracts c1 ON ob1.contract_id = c1.contract_id
    INNER JOIN $TH th1 ON ob1.product_type = th1."key"
WHERE
  th1.topic_key IN ($product_string) 
  AND ob1.fill_date < ? + 1
ORDER BY ob1.post_date ASC
  ;/; # 1-fill_date
  # NOTE: checking for classification will take a lot of effort, involves doing a word search akin to
  #                       bs.value_vector @@ plainto_tsquery('foswiki.all_languages',  'credit')
  # Conclusion: check for classification after downloading order list
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	
	
	$selectHandler->execute($fill_date);
	
	my ($order_id, $post_date, $fill_date, $product_type, $contract_id, $owner_key,$type_of_contract,$end_date ,$start_date,$term,$prod_class);
	$selectHandler->bind_col( 1, \$order_id );
	$selectHandler->bind_col( 2, \$post_date );
	$selectHandler->bind_col( 3, \$fill_date );
	$selectHandler->bind_col( 4, \$product_type );
	$selectHandler->bind_col( 5, \$term );
	$selectHandler->bind_col( 6, \$start_date );
	$selectHandler->bind_col( 7, \$end_date );
	$selectHandler->bind_col( 8, \$type_of_contract );
	$selectHandler->bind_col( 9, \$owner_key );
	$selectHandler->bind_col( 10, \$contract_id );
	my @table_input_form;
	require Foswiki::Contrib::DBIStoreContrib::DataformHandler;
	while ($selectHandler->fetch) {
		# get the classification
		my ($pw1,$pt1,$p_rev) = $handler->LoadWTRFromTHKey($product_type);
		bless $handler, *Foswiki::Contrib::DBIStoreContrib::DataformHandler;
		my $productTopic = Foswiki::Meta::->new($Foswiki::Plugins::SESSION,$pw1,$pt1);
		# WARNING: does not consider the possibility that the classification might change over revs
		Foswiki::Contrib::DBIStoreContrib::DataformHandler::loadFormOnly($handler,$productTopic);
		bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
		my @pfields = $productTopic->find('FIELD');
		foreach my $pf1 (@pfields) {
			$prod_class = $pf1->{'value'} if $pf1->{'name'} eq 'Classification';
		}
		# assemble order object
		my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->new($order_id);
		# set order_obj internal variables
		$order_obj->product_topic($product_type); #type vs topic is confusing
		$order_obj->post_date($post_date);
		my $xfill = $fill_date || -1;
		$order_obj->fill_date($xfill);
		$order_obj->handler($handler);
		# set contract_obj internal variables
		$order_obj->contract(Foswiki::Plugins::AccountsPlugin::Contracts::->new($contract_id));
		$order_obj->contract->term($term);
		$order_obj->contract->start($start_date);
		$order_obj->contract->end($end_date);
		$order_obj->contract->type($type_of_contract);
		$order_obj->contract->handler($handler);
		$order_obj->contract->owner($owner_key);
		# | User Name | Invoice | Post_Date | <input type="checkbox" name="fill_order" value="$order_id" /> |
		my @temp_row;
		push(@temp_row,$order_obj->_tag_mapper('Owner'));
		push(@temp_row,$order_obj->_tag_mapper('Invoice'));
		push(@temp_row,$order_obj->_tag_mapper('Order_Age').' Hours');
		push(@temp_row,'<input type="checkbox" name="fill_order:'.$order_obj->key.'" value="1" />');
		push(@table_input_form,'|'.join('|',@temp_row).'|') if $classification eq $prod_class;
		Foswiki::Plugins::AccountsPlugin::setOrder($order_obj);
	}
	my $body = join("\n",@table_input_form);
	$body = "\n| *Customer* | *Invoice* | *Order Age* | *Fill Order* |\n$body\n";
	
	# make the header
	my @form_header;
	push(@form_header,'<form action="%SCRIPTURLPATH{"accounts"}%/%WEB%/%TOPIC%" method="POST">');
	push(@form_header,'<input type="hidden" name="action" value="deliver_credit"/>');
	
	# make the footer
	my @form_footer;
	push(@form_footer,'<input class="foswikiSubmit" type="submit" value="Confirm Credits"/>');
	push(@form_footer,'</form>');
	
	
	return join("\n",@form_header).$body.join("\n",@form_footer);	
}


###################### withdrawal type actions #########################
=pod
---+ Withdrawal (provisioning or consuming services in which user account is debited)
   1. order - deduct credits from account, wait for order to be filled by the admin
   2. cancel - readds credits previously deducted back to the account
   3. fill - confirms that the admin has delivered the product
   4. consume - creates and updates consumption invoices
=cut
##########################################################################
=pod
---+ order_withdrawal

=cut
sub order_withdrawal {
	my $session = shift;
	my $request = $session->{request};
	my ($web,$topic) = ($session->{webName},$session->{topicName});
	my $user_key = $session->{user};
	my $current_time = time();
	my $requested_site_name = $request->param('site_name');
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();	

	
	my $gc_product_topic = $request->param('product_topic');
	my ($gcWeb,$gcTopic) = Foswiki::Func::normalizeWebTopicName($web,$gc_product_topic);
	my ($gcMeta,$gcText) = Foswiki::Func::readTopic($gcWeb,$gcTopic);
	# Form name (used to determine the type of product, ie DiD or Site)
	my @dummygcptf = $gcMeta->find('FORM');
	my $gc_product_topic_form = $dummygcptf[0]->{'name'};
	# Fields (JPY, JPYSetup, TermsOfService)
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
	$invoice_topic->topic('OrderInvoiceTemplateViewWithdrawal');
	$invoice_topic->load();
	my ($i,$t_exists) = (0,1);
	# we auto increment the number in order to make the topic name of the Invoice Topic unique
	while(!$t_exists){
		my $throw01 = $handler->LoadTHRow($gcWeb,$gcTopic.'Order'.$current_time.'N'.$i);
		$t_exists = 0 unless $handler->fetchTopicKeyByWT($gcWeb,$gcTopic.'Order'.$current_time.'N'.$i);
		$i += 1;
		die "Overloop" if $i>100;
	}
	$invoice_topic->web($gcWeb);
	$invoice_topic->topic($gcTopic.'Order'.$current_time.'N'.$i);
	
	my $invoice_text = $invoice_topic->text;

	# make sure to allow the user to see the invoice later
	my ($uwikiW,$uwikiT) = Foswiki::Func::normalizeWebTopicName($web,$session->{users}->getWikiName($user_key));
	$invoice_text .= "\n<!--\n   * Set ALLOWTOPICVIEW = $uwikiW.$uwikiT\n-->";
	$invoice_topic->text($invoice_text);
	
	# determine the amount to deduct from the person's account
	my ($currency,$amount);
	#$amount = _calculate_setup_price($gc_form_hash{'Price'},$gc_form_hash{'Setup'});
	$amount = $gc_form_hash{'Setup'};
	$amount = 0 unless $gc_form_hash{'Setup'};
	$currency = $gc_form_hash{'Currency'};

	# place an order under $user_key's name
	# a contract and product_type should be embedded in the order object
	my $order = Foswiki::Plugins::AccountsPlugin::Orders::->place_order({'product_type' => 'Credits', 'contract_topic'=> $contract_thkey, 
					'handler'=>$handler, 'owner' => $user_key, 'product_topic' => $product_thkey});

	# db prep, turn off autocommits so we can use transactions
	$handler->database_connection()->{AutoCommit} = 0;
	$handler->database_connection()->{RaiseError} = 1;
	
	eval{
		# defer constraints
		$handler->set_to_deferred();
		
		# we have to confirm payment of JPY,etc before we can fill this order
		$order->invoice_meta($invoice_topic);
		$order->fill_date(0);
		$order->contract->start($current_time);
		# deduct the credit, b/c it is an order_withdrawal
		$order->credit_decrease($amount,$currency);
		
		# save the order
		$order->save;
		
		$handler->database_connection()->commit;		
	};
	if ($@) {
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
	# now that the order has been put through, fill the order
	# some day, this section might do a Perl Fork, into a separate process
	# ... because these functions take a long time to run
	# ... we don't want user's http connections to time out
	if($gc_product_topic_form =~ m/(SitePriceSheetForm)$/ ){
		# we are creating a site
		require Foswiki::Plugins::AccountsPlugin::Sites;
		Foswiki::Plugins::AccountsPlugin::Sites::create_site($session,$gcMeta,$order);
	}
	elsif($gc_product_topic_form eq m/(DiDPriceSheetForm)$/){
		# we are reserving a phone
		require Foswiki::Plugins::AccountsPlugin::DiDs;
	}
	else{
		# nothing happens
	}

	#my $viewURL = $session->getScriptUrl( 1, 'view', $web, $topic );
	#$session->redirect( $session->redirectto($viewURL), undef, 1 );
	# mark order as filled when receipt of payment is confirmed manually
	# redirect the customer to the invoice page so that the customer can pay via the payment method
	#      listed on the invoice page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $invoice_topic->web, $invoice_topic->topic ) );
	$session->redirect($redirecturl);
}

# (monthly price,setup price)->the actual setup price
sub _calculate_setup_price {
	my $monthly = shift;
	my $setup = shift;

	return $monthly unless $setup;
	return $setup if $setup;
}

##########################################################################
=pod
---+ cancel_withdrawal
this can be done, either by the user or the admin.  this sets the fill_date to -100000 (-100,000)
=cut
sub cancel_withdrawal {
	my $session = shift;
	
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};
	require Foswiki::Plugins::AccountsPlugin::Credits;

	
	my $canceled_fill_date = -100000;

	my $invoice_page = $request->param('invoice_topic');
	my ($invoice_page_web,$invoice_page_topic) = Foswiki::Func::normalizeWebTopicName($web,$invoice_page);

	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$handler->LoadTHRow($invoice_page_web,$invoice_page_topic);
	my $invoice_key = $handler->fetchTopicKeyByWT($invoice_page_web,$invoice_page_topic); 
	
	# load the order object
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($handler,$invoice_key);
	# make sure this order has not already been canceled
	# make sure the order has not already been filled
	return undef if $order_obj->fill_date > 1 || $order_obj->fill_date < -100;

	# look up the current balance to make sure it is non-negative
	#Foswiki::Plugins::AccountsPlugin::Credits::_lookup_balance($user_key,$currency);
	# weird, $handler get converted to UserHandler obj
	$handler->database_connection()->{AutoCommit} = 0;
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;

	########### need to get amount to refund ###############
	require Foswiki::Plugins::AccountsPlugin::Credits;
	my $refund_amount;
	my $refund_currency;
	#TODO: prey that all the amounts are in the same currency
	require Foswiki::Plugins::AccountsPlugin::Credits;
	foreach my $cha01 (@{Foswiki::Plugins::AccountsPlugin::Credits::loadCreditHistoryByOrderID($order_obj->key)}){
		$refund_amount += $cha01->{'amount'};
		$refund_currency = $cha01->{'currency'}; 
	}

	eval{
		# defer constraints
		$handler->set_to_deferred();
		

		$order_obj->fill_date($canceled_fill_date);
		$order_obj->contract->start($canceled_fill_date);
		# add back the credits that were charged in the incorrect order
		if($refund_amount !=0 && $refund_amount){
			# some products have no Setup Fees
			$order_obj->credit_increase($refund_amount,$refund_currency);
		}
		
		$order_obj->save(); # (functional equivalent to saving)

		$handler->database_connection()->commit;	
	};
	if ($@) {
		$handler->database_connection()->errstr;

		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Sorry.',
                params => ['order_credit']
		);
		
	}
    # redirect to the new page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $session->{webName}, $session->{topicName} ) );
	$session->redirect($redirecturl);
	#die "nothing: ".$order_obj_list[0]->key;
	#_add_credits_to_account($handler, user_key, amount, product_id);
}

##########################################################################
=pod
---+ fill_withdrawal
this can be done, either by the user or the admin.  this sets the fill_date to time() and is recognition that the order has been filled.
=cut
sub fill_withdrawal {
	my $session = shift;
	
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};

	
	# set the fill order to the current time
	my $fill_date = time();

	my $invoice_page = $request->param('invoice_topic');
	my ($invoice_page_web,$invoice_page_topic) = Foswiki::Func::normalizeWebTopicName($web,$invoice_page);

	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$handler->LoadTHRow($invoice_page_web,$invoice_page_topic);
	my $invoice_key = $handler->fetchTopicKeyByWT($invoice_page_web,$invoice_page_topic); 
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($handler,$invoice_key);
	# make sure this order has not already been canceled
	# make sure the order has not already been filled
	return undef if $order_obj->fill_date > 1 || $order_obj->fill_date < -100;
	
	# find out what kind of product it is, ie a Site or a DiD
	
	
	# look up the current balance to make sure it is non-negative
	#Foswiki::Plugins::AccountsPlugin::Credits::_lookup_balance($user_key,$currency);
	# weird, $handler get converted to UserHandler obj
	$handler->database_connection()->{AutoCommit} = 0;
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	eval{
	
		# defer constraints
		$handler->set_to_deferred();
		
		$order_obj->fill_date($fill_date);
		$order_obj->contract->start($fill_date);
		$order_obj->save(); # (functional equivalent to saving)

		$handler->database_connection()->commit;
	};
	if ($@) {
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Order not confirmed.  Sorry.',
                params => ['order_credit']
		);
		
	}
    # redirect to the new page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $session->{webName}, $session->{topicName} ) );
	$session->redirect($redirecturl);
	#die "nothing: ".$order_obj_list[0]->key;
	#_add_credits_to_account($handler, user_key, amount, product_id);
}


##########################################################################
=pod
---+ consume_withdrawal
done by admin on a regular bases, creates and updates invoices for users and documents the cost of users' calls, site usage, etc
=cut
my $fx_rates = { 'JPY' => 
	{'2010' => 
		{'1' => 91.3166},
		{'2' => 90.2073},
		{'3' => 90.6785},
		{'4' => 93.5382},
		{'5' => 92.151},
		{'6' => 90.9196},
		{'7' => 87.4993},
		{'8' => 85.3309},
		{'9' => 84.3766},
		{'10' => 81.7948},
		{'11' => 82.513},
		{'12' => 83.2909}
	},
	{'2011' => 
		{'1' => 82.6861},
		{'2' => 82.6304},
		{'3' => 81.7198},
		{'4' => 83.25},
		{'5' => 81.1749},
		{'6' => 80.4486},
		{'7' => 79.4025},
		{'8' => 76.9956},
		{'9' => 76.7935},
		{'10' => 76.6537},
		{'11' => 77.4707},
		{'12' => 77.8113}
	},
	{'2012' => 
		{'1' => 76.9677},
		{'2' => 78.4585},
		{'3' => 82.4771},
		{'4' => 81.4999}
	}
};


sub consume_withdrawal {
	my $session = shift;
	
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};
	require Foswiki::Time;
	# get the accounting period first (by year-month)
	# from that we get 2010-04-01 00:00 <= time < 2010-05-01 00:00 if the year=2010 and month=04
	my ($year,$month) = ($request->param('year'),$request->param('month'));
	my ($end_year,$end_month) = 0;
	if($month + 1 > 12){
		$end_year += 1;
		$end_month = 1
	}
	else{
		$end_year = $year;
		$end_month = $month + 1;
	}
	# let's just use GMT time
	my ($start_epoch,$end_epoch) = (Foswiki::Time::parseTime("$year-$month-01 00:00"),Foswiki::Time::parseTime("$end_year-$end_month-01 00:00"));
	return undef unless $start_epoch && $end_epoch;

	# need the current time to see if we are just updating an order page, or creating a new order page
	my $old_end_epoch = $end_epoch;
	$end_epoch = time() if $end_epoch > time();
	
	# get Site Man Seconds for each Site
	require Foswiki::Plugins::AccountsPlugin::Sites;
	my $site_hash = Foswiki::Plugins::AccountsPlugin::Sites::all_site_man_seconds($start_epoch,$end_epoch);

	# get DiD man seconds
	require Foswiki::Plugins::AccountsPlugin::DiDs;
	# skipping this b/c it is too complicated without new inventory system
	#my $did_hash = Foswiki::Plugins::AccountsPlugin::DiDs::all_did_seconds($start_epoch,$end_epoch);
	# get phone minutes
	my $cdr_hash = Foswiki::Plugins::AccountsPlugin::DiDs::all_billed_seconds($start_epoch,$end_epoch);

	######## create all of the order/invoice topics for all users ########
	
	# 1. get the "product_topic" for consumption tracking (topic_key = 'c2d10652-8e10-11e1-9b50-2b9e3baf19b4')
	# 2. let the contract topic page be the same as the product page
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();	
	my ($contract_wn,$contract_tn) = Foswiki::Func::normalizeWebTopicName('Main','ConsumptionProduct20120424') ;
	# weird bug with $handler magically becoming a UserHandler
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $contract_throw = $handler->LoadTHRow($contract_wn,$contract_tn);
	my $contract_thkey = $contract_throw->{'key'};
	my $product_thkey = $contract_thkey;

	# Get the Product T_H_key (from the gift card topic)
	my $product_throw = $handler->LoadTHRow($contract_wn,$contract_tn);
	my $product_thkey = $product_throw->{'key'};
	
	# we have to create an order for each user
	require Foswiki::Plugins::AccountsPlugin::Users;
	my $user_hash = Foswiki::Plugins::AccountsPlugin::Users::get_customer_list($handler);


	$handler->database_connection()->{AutoCommit} = 0;
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	eval{
	
		# defer constraints
		$handler->set_to_deferred();
		my $fill_date = $end_epoch;
		my $start_date = $start_epoch;
	
		# loop through the users
		foreach my $user01key (keys %{$user_hash}){

			# this only works for consumption orders that don't exist
			my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->place_order({'product_type' => 'Credits', 'contract_topic'=> $contract_thkey, 
					'handler'=>$handler, 'owner' => $user01key, 'product_topic' => $product_thkey});
					$order_obj->fill_date($fill_date);
			$order_obj->contract->start($start_epoch);

			# calculate the amounts needed
			my $amount_hash;
			$amount_hash->{'JPY'} = 0;
			$amount_hash->{'USD'} = 0;
			$amount_hash->{'BTC'} = 0;
			my $amount = 0;
			my $numOfCalls;
			$numOfCalls = $cdr_hash->{$user01key}->{'number_of_calls'};
			$numOfCalls = 0 unless $numOfCalls;
			# go through minutes
			my $minutes_text = "\n---++ Minutes\n";

			foreach my $call01uuid (keys %{$cdr_hash->{$user01key}}){
				# $cdr_hash->{$user01key}->{$call01uuid};

				my $costA = $cdr_hash->{$user01key}->{$call01uuid}->{'cost_a_cost'};
				my $costB = $cdr_hash->{$user01key}->{$call01uuid}->{'cost_b_cost'};
				my $currencyA = $cdr_hash->{$user01key}->{$call01uuid}->{'cost_a_currency'};
				my $currencyB = $cdr_hash->{$user01key}->{$call01uuid}->{'cost_b_currency'};
				my $billsec = $cdr_hash->{$user01key}->{$call01uuid}->{'billsec'};
				
				
				# convert everything to JPY
				if($currencyA == 'USD'){
					$amount += ($fx_rates->{$currencyA}->{$year}->{$month})*$costA;
				}
				else{
					$amount += $costA;
				}
				if($currencyB == 'USD' && $costB){
					$amount += ($fx_rates->{$currencyB}->{$year}->{$month})*$costB;
				}
				elsif($costB){
					$amount += $costB;
				}

			}

			$minutes_text .= "\n| Minutes for $numOfCalls Calls | JPY $amount |\n\n";
			# reset $amount to calculate 
			my $pre_amount = $amount;
			$amount = 0;
			my $site_text = "\n---++ Site Hosting\n\n";

			foreach my $site01key (keys %{$site_hash->{'users'}->{$user01key}}){
				my $manseconds = $site_hash->{$site01key}->{'man_seconds'};
				$amount += 100*$manseconds/60/60/24/30;
				$site_text .= "| Site: ".$site_hash->{$site01key}->{'site_name'}." | ".$manseconds/60.0/60.0/24.0/30.0 ." people a month | JPY ".ceil(100*$manseconds/60.0/60.0/24.0/30.0)."|\n";
			}

			$site_text .= "|| Total: | JPY ".ceil($amount)."|\n\n";
			
			# set amount to the total
			$amount += $pre_amount;
			
			# get the total and extract the sales tax.
			my $total_text = "\n---++ Total\n";
			
			# sales tax is 5%
			$total_text .= "| Total | JPY \%STARTSECTION{\"total\"}\%".$amount.
				"\%ENDSECTION{\"salestax\"}\% |\n| Sales Tax (Incl) | \%STARTSECTION{\"salestax\"}\%".$amount/(1-.05).
					"\%ENDSECTION{\"salestax\"}\% |";
			
			# setup a new invoice meta
			$order_obj->invoice_meta_load();
			
			my $meta_text = $order_obj->invoice_meta->text;
			$meta_text .= "\n---+ Cost Calculation\n".$site_text.$minutes_text.$total_text;
			$order_obj->invoice_meta->text($meta_text);
			$order_obj->credit_decrease($amount);
			$order_obj->save(); # (functional equivalent to saving)

		}

		$handler->database_connection()->commit;

	};
	if ($@) {
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Order not confirmed.  Sorry.',
                params => ['order_credit']
		);
		
	}

}

=pod
---+ order_deposit

=cut
sub order_deposit {
	my $session = shift;
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	# payment method -> convert to topic key
	my $payment_method = $request->param('payment_method');
	my ($paymentWeb,$paymentTopic) = Foswiki::Func::normalizeWebTopicName($web,$payment_method);
	$handler->LoadTHRow($paymentWeb,$paymentTopic);
	my $payment_method_key = $handler->fetchTopicKeyByWT($paymentWeb,$paymentTopic);
	# get current time now, in order to be consistent later
	my $current_time = time();
	
	# Create the Product Topic (gift card) object, load it with the pricing information
	my $gc_product_topic = $request->param('product_topic');
	my ($gcWeb,$gcTopic) = Foswiki::Func::normalizeWebTopicName($web,$gc_product_topic);
	my ($gcMeta,$gcText) = Foswiki::Func::readTopic($gcWeb,$gcTopic);
	# Fields (Number, CountryCode, Owner, Supplier)
	my @gcFields;
	my %gc_form_hash;
	my @gcFields = $gcMeta->find( 'FIELD' );
	foreach my $xf (@gcFields){
			$gc_form_hash{$xf->{'name'}} = $xf->{'value'};
	}
	my $deposit_amount = $gc_form_hash{'JPY'};
	# need to clean up $deposit_amount (make sure that it is a real number)
	if($deposit_amount =~ /^\s*([0-9]+)\s*$/){
		$deposit_amount = $1;
		throw Foswiki::OopsException(
                'attention',
                def    => 'No Credits Ordered.',
                params => ['order_credit']
		) unless $deposit_amount;
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
	# make sure to allow the user to see the invoice later
	my ($uwikiW,$uwikiT) = Foswiki::Func::normalizeWebTopicName($web,$session->{users}->getWikiName($user_key));
	$invoice_text .= "\n<!--\n   * Set ALLOWTOPICVIEW = $uwikiW.$uwikiT\n-->";
	$invoice_topic->text($invoice_text);
	# put the payment code in the invoice as a meta preference
	#_set_up_payment_code($handler,$invoice_topic,$payment_method_key);

	

	# the Order Invoice is Preset!
	$invoice_topic->putKeyed( 'FORM',{ name => 'Main.OrderInvoiceForm' } );
	# verify payment method linked is legal
	#my $legal_pay = Foswiki::Func::getPreferencesValue('ACCOUNTS_ALLOWEDPAYMENTMETHODS');
	#die "payment is not available ($payment_method_key) in ($legal_pay)" unless $legal_pay =~ m/$payment_method_key/;
	# put in the payment method into the Form Field
	$invoice_topic->putKeyed( 'FIELD',{ name => 'PaymentMethod', title => 'PaymentMethod', value => $paymentWeb.'.'.$paymentTopic } );
	$invoice_topic->putKeyed( 'FIELD',{ name => 'Currency', title => 'Currency', value => 'JPY' } );
	
	
	# db prep, turn off autocommits so we can use transactions
	$handler->database_connection()->{AutoCommit} = 0;
	$handler->database_connection()->{RaiseError} = 1;

	# place an order under $user_key's name
	# a contract and product_type should be embedded in the order object
	my $order = Foswiki::Plugins::AccountsPlugin::Orders::->place_order({'product_type' => 'Credits', 'contract_topic'=> $contract_thkey, 
					'handler'=>$handler, 'owner' => $user_key, 'product_topic' => $product_thkey});
	$order->invoice_meta($invoice_topic);

	eval{
		# defer constraints
		$handler->set_to_deferred();

		# we have to confirm payment of JPY,etc before we can fill this order
		$order->fill_date(0);
		$order->contract->start(0);
		
		# save the order
		$order->save;
		
		$handler->database_connection()->commit;		
	};
	if ($@) {
		#die "$@";

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
	# redirect the customer to the invoice page so that the customer can pay via the payment method
	#      listed on the invoice page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $invoice_topic->web, $invoice_topic->topic ) );
	$session->redirect($redirecturl);
	
	
	
}
=pod
---+ fill_deposit
this is done after payment is confirmed by an admin.  this is after payment is confirmed, and this action can only be performed by someone in the admin group.
=cut
sub fill_deposit {
	my $session = shift;
	
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};

	my $current_time = time();
	my $fill_date = $current_time;
	
	my $invoice_page = $request->param('invoice_topic');
	my ($invoice_page_web,$invoice_page_topic) = Foswiki::Func::normalizeWebTopicName($web,$invoice_page);
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$handler->LoadTHRow($invoice_page_web,$invoice_page_topic);
	my $invoice_key = $handler->fetchTopicKeyByWT($invoice_page_web,$invoice_page_topic); 
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($handler,$invoice_key);

	# skip this order if it has already been filled or canceled
	return undef if $order_obj->fill_date > 1 || $order_obj->fill_date < -100;
	
	$order_obj->fill_date($fill_date);
	$order_obj->contract->start($fill_date);
	
	# weird, $handler get converted to UserHandler obj
	$handler->database_connection()->{AutoCommit} = 0;
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	eval{
		# defer constraints
		$handler->set_to_deferred();

		# get amount from product page (time dependent, so we need the revision too)
		my ($pw1,$pt1,$rev1) = $handler->LoadWTRFromTHKey($order_obj->product_topic);
		my $productTopic = Foswiki::Meta::->new($Foswiki::Plugins::SESSION,$pw1,$pt1);
		$productTopic->load($rev1);
		my @fields = $productTopic->find('FIELD');
		my $amount = 0;
		my %fd1_form_hash;
		foreach my $fd1 (@fields) {
			$fd1_form_hash{$fd1->{'name'}} = $fd1->{'value'};
		}
		# figure out the amount, starting with JPY->USD->BTC
		my $currency;
		if($fd1_form_hash{'JPY'}){
			$amount = $fd1_form_hash{'JPY'};
			$currency = 'JPY';
		}
		elsif($fd1_form_hash{'USD'}){
			$amount = $fd1_form_hash{'USD'};
			$currency = 'USD';			
		}
		elsif($fd1_form_hash{'BTC'}){
			$amount = $fd1_form_hash{'BTC'};
			$currency = 'BTC';
		}
		
		die "No amount $amount" unless $amount;
		# add the credits to the user account
		# ($handler, $product_th_key, $owner_key, amount,currency)-> adds credits to the user's account
		$order_obj->credit_increase($amount,$currency);
			
		# mark the user's order as filled
		$order_obj->save();
		$handler->database_connection()->commit;
	};

	if ($@) {
		die " Sucks: $@";
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Order not confirmed.  Sorry.',
                params => ['order_credit']
		);
		
	}
    # redirect to the new page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $session->{webName}, $session->{topicName} ) );
	$session->redirect($redirecturl);
	#die "nothing: ".$order_obj_list[0]->key;
	#_add_credits_to_account($handler, user_key, amount, product_id);
}

=pod
---+ cancel_deposit
this can be done, either by the user or the admin.  this sets the fill_date to -100000 (-100,000)
=cut
sub cancel_deposit {
	my $session = shift;
	
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $user_key = $session->{user};

	my $fill_date = -100000;

	my $invoice_page = $request->param('invoice_topic');
	my ($invoice_page_web,$invoice_page_topic) = Foswiki::Func::normalizeWebTopicName($web,$invoice_page);

	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$handler->LoadTHRow($invoice_page_web,$invoice_page_topic);
	my $invoice_key = $handler->fetchTopicKeyByWT($invoice_page_web,$invoice_page_topic); 
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($handler,$invoice_key);

	# make sure the order has not already been filled
	return undef unless $order_obj->fill_date < 1;
	$order_obj->fill_date($fill_date);
	$order_obj->contract->start($fill_date);

	# weird, $handler get converted to UserHandler obj
	$handler->database_connection()->{AutoCommit} = 0;
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	eval{
		# defer constraints
		$handler->set_to_deferred();
		$order_obj->save();
		$handler->database_connection()->commit;
	};

	if ($@) {
		#die " Sucks: $@";
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Order not confirmed.  Sorry.',
                params => ['order_credit']
		);
		
	}
    # redirect to the new page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $session->{webName}, $session->{topicName} ) );
	$session->redirect($redirecturl);
	#die "nothing: ".$order_obj_list[0]->key;
	#_add_credits_to_account($handler, user_key, amount, product_id);
}

##########################################################################
=pod
---+ credit_increase($amount,$currency)->
increases the credit balance of the owner of the contract, however it requires a new topic revision of the invoice topic
=cut
sub credit_increase {
	my $this = shift;
	my $amount = shift;
	my $currency = shift;

	# add some meta data to the invoice topic, so that when the invoice topic is saved
	#     the credit_history insert will be made	
	$this->invoice_meta->putKeyed('CREDITBALANCE',{name=> 'CREDITBALANCE',balance => abs($amount), currency => $currency, owner=> $this->contract->owner});
	
	#require Foswiki::Plugins::AccountsPlugin::Credits;
	# need topic_history_key of new revision 
	#Foswiki::Plugins::AccountsPlugin::Credits::_add_credits_to_account( $this->handler, $this->key, $this->contract->owner ,abs($amount), $currency);
}
##########################################################################
=pod
---+ credit_decrease($amount,$currency)
decrease the credit balance of the owner of the contract, however it requires a new topic revision of the invoice topic
=cut
sub credit_decrease {
	my $this = shift;
	my $amount = shift;
	my $currency = shift;
	
	# add some meta data to the invoice topic, so that when the invoice topic is saved
	#     the credit_history insert will be made
	$this->invoice_meta->putKeyed('CREDITBALANCE',{name=> 'CREDITBALANCE',balance => -1*abs($amount), currency => $currency, owner=> $this->contract->owner});
	
	#require Foswiki::Plugins::AccountsPlugin::Credits;
	# need topic_history_key of new revision 
	#Foswiki::Plugins::AccountsPlugin::Credits::_deduct_credits_from_account( $this->handler, $this->key, $this->contract->owner ,abs($amount), $currency);
}

=pod
---+ DWOLLAPAY
	%DWOLLAPAY{topic="%BASEWEB%.%BASETOPIC%"}%
=cut
sub dwolla_pay {
	my ($inWeb,$inTopic, $args) = @_;
	my $session = $Foswiki::Plugins::SESSION;
	
	# get the Order web,topic pair
	require Foswiki::Func;
	my $order_topic_WT = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	$order_topic_WT = $session->{webName}.'.'.$session->{topicName} unless $order_topic_WT;
	
	# get the order id
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	my $order_id = $topic_handler->_convert_WT_Topics_in($order_topic_WT);
	
	return undef unless $order_id;
	
	# load the order object
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($topic_handler,$order_id);
	return undef unless $order_obj;
	# create the dwolla object
	require Foswiki::Plugins::AccountsPlugin::Dwolla;
	my $dwolla_obj = Foswiki::Plugins::AccountsPlugin::Dwolla::->new($order_obj);
	
	# return the dwolla form html
	return $dwolla_obj->form_html;
}

=pod
---+ BITCOINORDER
	%BITCOINORDER{"address/balance" topic="ordertopic"}%
=cut
sub bitcoin_order {
	my ($inWeb,$inTopic, $args) = @_;
	my $session = $Foswiki::Plugins::SESSION;
	
	# address or balance?
	my $main_arg = Foswiki::Func::extractNameValuePair( $args );
	
	# get the Order web,topic pair
	require Foswiki::Func;
	my $order_topic_WT = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	$order_topic_WT = $session->{webName}.'.'.$session->{topicName} unless $order_topic_WT;
	
	# get the order id
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	my $order_id = $topic_handler->_convert_WT_Topics_in($order_topic_WT);
	
	
	return '' unless $order_id;
	
	
	# load the order object
	my $order_obj = Foswiki::Plugins::AccountsPlugin::Orders::->load($topic_handler,$order_id);
	return undef unless $order_obj;
	# create the bitcoin object
	require Foswiki::Plugins::AccountsPlugin::BitCoin;
	my $bitcoin_obj = Foswiki::Plugins::AccountsPlugin::BitCoin::->new($order_obj);
	
	# return the bitcoin information
	return $bitcoin_obj->address if $main_arg eq 'address';
	return $bitcoin_obj->balance if $main_arg eq 'balance';
}

1;
__END__
