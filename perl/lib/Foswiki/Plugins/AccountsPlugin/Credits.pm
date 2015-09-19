package Foswiki::Plugins::AccountsPlugin::Credits;

use strict;
use Foswiki::Func();
use Foswiki::Plugins::AccountsPlugin::Orders();



my %SourceToMetaHash = (
'saveTopic' => {  ### - Start ####################################
### ($topic_handler is $this) @vars=($topicObject, $cUID,\%th_row_ref)
'CREDITBALANCE' => sub { 
	my ($handler,$topicObject, $cUID,$th_row_ref) = @_;
	my $cbref = $topicObject->get('CREDITBALANCE');
	return undef unless $cbref->{currency} && $cbref->{balance};
	
	# do an sql insert
	my $CH = $handler->getTableName('Credit_History');
	
	# TODO: mitigate the risk of giving too much money back to customers
	my $insertStatement = qq/
  INSERT INTO $CH (user_key, amount, currency, key)
VALUES (?,?,?,?)
  ;  /; # 1-amount,2-currency,3-topic_history_key of the order invoice page
	my $insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($cbref->{owner},$cbref->{balance},$cbref->{currency},$th_row_ref->{key});
	return 1;
	}
}
);
##########################################################################
=pod
---+ listener($amount,$currency)
decrease the credit balance of the owner of the contract, however it requires a new topic revision of the invoice topic
=cut

sub listener {
	my $site_handler = shift;
	my $sourcefunc = shift;
	my @vars = @_;
	# will need this after calling listeners in order to set the site_handler back to what it was before
	my $currentClass = ref($site_handler);
	# need to initialize the object
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $this = Foswiki::Contrib::DBIStoreContrib::TopicHandler->init($site_handler);

	# these are pieces of the Meta topicObject		
	my @MetaHashObjects = ('CREDITBALANCE');
	my $sourcFuncRef = $SourceToMetaHash{$sourcefunc};
	foreach my $MetaHash (@MetaHashObjects) {
		$SourceToMetaHash{$sourcefunc}{$MetaHash}->($this,@vars) if exists($SourceToMetaHash{$sourcefunc}{$MetaHash});
	}
	# return handler to previous state
	bless $this, $currentClass;

}


# need to insert a meta preference into the invoice
sub _set_up_payment_code {
	my ($handler,$invoice_topic,$payment_method_key) = @_;
=pod

<div class="foswikiHidden">
   * Set DENYTOPICVIEW =  
   * Set ALLOWTOPICCHANGE = Main.AdminGroup
   * Set ALLOWTOPICRENAME = Main.AdminGroup
</div>
=cut
	# find out whether the payment method is through a bank, bitcoin, or something else
}

# ($handler,$web,$topic)-> link_to_latest
sub _getContractKey {
	my $handler = shift;
	my $web = shift;
	my $topic = shift;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	my $throw = $topic_handler->LoadTHRow($web,$topic);
	bless $handler, *Foswiki::Contrib::DBIStoreContrib::Handler;
	return $throw->{key};
}
# ($handler, $order_id, $user_key, amount,currency)-> adds credits to the user's account
sub _add_credits_to_account {
	my $handler = shift;
	my $order_id = shift;
	my $user_key = shift;
	my $amount = shift;
	my $currency = shift;
	#return undef unless $amount > 0;
	$amount = abs($amount);
	# do an sql insert
	my $CH = $handler->getTableName('Credit_History');
	
	my $insertStatement = qq/
  INSERT INTO $CH (user_key, amount, timestamp_epoch, order_id, currency)
VALUES (?,?,?,?, ?);
	/;
	my $insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($user_key,$amount,time(),$order_id, $currency);

	return $user_key;
}
# ($handler, $order_id, $user_key, amount,currency)-> deducts credits to the user's account
sub _deduct_credits_from_account {
	my $handler = shift;
	my $order_id = shift;
	my $user_key = shift;
	my $amount = shift;
	my $currency = shift;
	#return undef unless $amount > 0;
	$amount = abs($amount);
	$amount = -1*$amount;
	# do an sql insert
	my $CH = $handler->getTableName('Credit_History');
	
	my $insertStatement = qq/
  INSERT INTO $CH (user_key, amount, timestamp_epoch, order_id, currency)
VALUES (?,?,?,?, ?);
	/;
	my $insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($user_key,$amount,time(),$order_id, $currency);

	return $user_key;
}
#  ($handler, $order_obj->key, $order_obj->contract->owner) -> insert transaction to undo previous transaction
sub _refund_credits_to_account {
	my $handler = shift;
	my $order_id = shift;
	my $user_key = shift;
	
	# do an sql insert
	my $CH = $handler->getTableName('Credit_History');
	
	# TODO: mitigate the risk of giving too much money back to customers
	my $insertStatement = qq/
  INSERT INTO $CH (user_key, amount, timestamp_epoch, order_id, currency)
SELECT ch.user_key, -1*ch.amount, ?, ch.order_id,  ch.currency 
FROM $CH ch
WHERE ch.order_id = ?
GROUP BY ch.order_id, ch.amount, ch.currency, ch.user_key
HAVING COUNT(ch.order_id) = 1
  ;  /; # 1-time, 2-order_id
	my $insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute(time(),$order_id);

	return $order_id;
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
# displays the credit balance of the user who is logged in
# the default currency is JPY
sub get_credit_balance {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins;
	my $session = $Foswiki::Plugins::SESSION;
	require Foswiki::Func;
	my $currency = Foswiki::Func::extractNameValuePair( $args, 'Currency' );
	$currency = 'JPY' unless $currency;
	
	my $user_key = $session->{user};
	return _lookup_balance($user_key,$currency);
}

# displays the credit balance of the user who is logged in
# the default currency is JPY
sub get_credit_history {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins;
	my $session = $Foswiki::Plugins::SESSION;
	require Foswiki::Func;
	my $Column = Foswiki::Func::extractNameValuePair( $args );
	my $wtpair = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	my ($ow1,$ot2) = Foswiki::Func::normalizeWebTopicName($inWeb,$wtpair);
	($ow1,$ot2) = ($inWeb,$inTopic) unless $wtpair;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $order_id = $topic_handler->_convert_WT_Topics_in($ow1.'.'.$ot2);
	return undef unless $order_id;
	
	my $ch_row = loadCreditHistoryByOrderID($order_id);
	return fetchCrediHistory($order_id,$Column);
}


# TODO: update the cache
# (user_key,currency)-> current balance
sub _lookup_balance{
	my $user_key = shift;
	my $currency = shift;
	
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $cb = $topic_handler->getTableName('Credit_Balance');
	my $selectStatement = qq/SELECT cb.balance
FROM $cb cb
WHERE  cb.user_key = ? AND cb.currency = ?;/;# 1-user_key, 2-currency
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($user_key,$currency);
	my $balance;
	$selectHandler->bind_col( 1, \$balance );
	while ($selectHandler->fetch) {
		return $balance;
	}
	return undef;
}

# ($order_id,$ch_key,$column_name)->ch_row{timestamp_epoch,owner,currency,balance}
sub fetchCrediHistory {
	my $order_id = shift;
	my $ch_key = shift;
	my $col_name = shift;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	return $topic_handler->{credit_cache}->{$order_id}->{$ch_key}->{$col_name};
}
# ($order_id,$ch_key,$column_name,$column_value)-> puts pair in handler->{credit_cache}
sub putCreditHistory {
	my $order_id = shift;
	my $ch_key = shift;
	my $col_name = shift;
	my $col_val = shift;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	$topic_handler->{credit_cache}->{$order_id}->{$ch_key}->{$col_name} = $col_val;
	return $topic_handler->{credit_cache}->{$order_id}->{$ch_key}->{$col_name};
}
# ($order_id)->load credit history
sub loadCreditHistoryByOrderID {
	my $order_id = shift;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();	
	my $ch_row;
=pod
my $ch_row = {
		'user_key' => fetchCrediHistory($order_id,'user_key'),
		'amount' => fetchCrediHistory($order_id,'amount'),
		'timestamp_epoch' => fetchCrediHistory($order_id,'timestamp_epoch'),
		'currency' => fetchCrediHistory($order_id,'currency')
	};

	my $need_to_update_bool = 1;
	foreach my $cn01 (keys %$ch_row){
		$need_to_update_bool = 0 unless $ch_row->{$cn01};
	}
=cut
	my @ch_row_Array;
	my $need_to_update_bool = 0;
	if(!$need_to_update_bool){
		# we need to go to the database and fetch
		my $ch = $topic_handler->getTableName('Credit_History');
		my $ob = $topic_handler->getTableName('Order_Book');
		my $th = $topic_handler->getTableName('Topic_History');
	my $selectStatement = qq/
SELECT 
  ch.user_key,
  ch.amount,
  th.timestamp_epoch,
  ch.currency,
  ch."key"
FROM 
  $th th
	INNER JOIN $ob ob ON th.topic_key = ob.order_id
	INNER JOIN $ch ch ON ch."key" = th."key"
WHERE
  ob.order_id = ? ;/;# 1-order_id
		my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
		$selectHandler->execute($order_id);
		my ($owner,$amount,$post_date,$currency,$ch_key);
		$selectHandler->bind_col( 1, \$owner );
		$selectHandler->bind_col( 2, \$amount );
		$selectHandler->bind_col( 3, \$post_date );
		$selectHandler->bind_col( 4, \$currency );
		$selectHandler->bind_col( 5, \$ch_key );
		while ($selectHandler->fetch) {
			$ch_row->{'user_key'} = putCreditHistory($order_id,$ch_key,'user_key',$owner);
			$ch_row->{'amount'} = putCreditHistory($order_id,$ch_key,'amount',$amount);
			$ch_row->{'timestamp_epoch'} = putCreditHistory($order_id,$ch_key,'timestamp_epoch',$post_date);
			$ch_row->{'currency'} = putCreditHistory($order_id,$ch_key,'currency',$currency);
			push(@ch_row_Array,$ch_row); 
		}		
	}
	return \@ch_row_Array;
}


1;
__END__


---+ Creates new credit accounts from the foswiki."Users" table
INSERT INTO accounts."Credits_Balance" (user_key, balance, currency)  
   (SELECT u1."key", 0, 'USD' FROM   foswiki."Users" u1 
			INNER JOIN foswiki."Sites" s1 ON u1.site_key = s1."key" 
			LEFT JOIN accounts."Credits_Balance" cb ON u1."key" = cb.user_key AND cb.currency = 'USD'
		WHERE s1.current_site_name = 'e-flamingo.net' AND cb.user_key IS NULL )

