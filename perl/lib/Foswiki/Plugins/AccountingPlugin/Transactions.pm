package Foswiki::Plugins::AccountingPlugin::Transactions;

use strict;
use Foswiki::Func();
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use Foswiki::UI::Accounting();

# create a new Transaction
sub new {
	my $class = shift;
	my $this;
	$this->{'balance'} = 0;
	$this->{'enter_date'} = time();
	bless $this, $class;
	
	return $this;
}
# ()->balance
sub balance {
	my $this = shift;
	return $this->{'balance'};
}
# uses Foswiki::Time
# converts 2011-12-23 -> epoch seconds
# returns epoch seconds
sub post_date_convert {
	my $this = shift;
	my $date_string = shift;
	return $this->post_date unless $date_string;
	require Foswiki::Time;
	my $post_epoch = Foswiki::Time::parseTime($date_string);
	# after converting to epoch seconds
	return $this->post_date($post_epoch);

}
# getter and setter, only works with epoch seconds
sub post_date {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'post_date'} = $x;
		return $x;
	}
	else{
		return $this->{'post_date'};
	}		
}

# getter and setter, only works with epoch seconds
sub enter_date {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'enter_date'} = $x;
		return $x;
	}
	else{
		return $this->{'enter_date'};
	}		
}
# getter and setter
sub user {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'user_key'} = $x;
		return $x;
	}
	else{
		return $this->{'user_key'};
	}		
}

# getter and setter
sub handler {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'handler'} = $x;
		return $x;
	}
	else{
		return $this->{'handler'};
	}		
}

# getter and setter
sub key {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'key'} = $x;
		return $x;
	}
	else{
		return $this->{'key'};
	}		
}

# ($split)-> nothing, adds split amount to the balance
sub add_split {
	my $this = shift;
	my $new_split = shift;
	# make sure the split is not empty
	return undef unless $new_split->amount && $new_split->account;

	# check if the account already has a linked split
	my $old_split = $this->{'splits'}->{$new_split->account};
	if($old_split){
		# add the balance
		$this->{'balance'} += $new_split->amount;
		# account already accounted for, so delete it
		# merge the old balance into the new balance
		$new_split->amount($old_split->amount + $new_split->amount);
		$this->remove_split($old_split->account);
	}
	else{
		$this->{'balance'} += $new_split->amount;
	}
	$this->{'splits'}->{$new_split->account} = $new_split;
	return $new_split;
}

# ($account_key)-> remove split 
sub remove_split {
	my $this = shift;
	my $account_key = shift;
	$this->{'splits'}->{$account_key} = undef; 
}
# ($account_key)->split
sub get_split {
	my $this = shift;
	my $account_key = shift;
	return $this->{'splits'}->{$account_key};
}
# ()->%splits
sub get_all_splits {
	my $this = shift;
	return $this->{'splits'};
}
# generates the key for transaction, and all of the splits
# 1-user_key, 2-post_date, 3-enter_date
sub generate_key {
	my $this = shift;
	$this->key( substr(sha1_hex( $this->user, $this->post_date, $this->enter_date ), 0, - 8) );
	foreach my $account (keys %{$this->get_all_splits()}){
		my $split = $this->get_split($account);
		$split->generate_key($this->key);
	}
	return $this->key;
}
# save the transaction, as well as all of the splits
sub save {
	my $this = shift;
	
	my ($key,$user,$post_date,$enter_date) = ($this->key,$this->user,$this->post_date,$this->enter_date);
	
	$enter_date = time() unless $enter_date;
		
	die "Input Data Error" unless $key && $user && $enter_date;
	my $handler = $this->handler;
	# save all of the splits first
	foreach my $account (keys %{$this->get_all_splits()}){
		my $split = $this->get_split($account);
		$split->handler($this->handler);
		$split->transaction_key($this->key);
		my $bool = $split->save();
		#return undef unless $bool;
		# check to see if this person as change rights to the account topic
		# have to get web,topic pair b/c Foswiki::Func not equipped to deal with topic keys
		bless $handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler; #mystery why, but this line is necessary
		my ($inWeb,$inTopic) = @{$handler->_convert_WT_Topics_out($account)};
		$bool = Foswiki::Func::checkAccessPermission('CHANGE', $this->user, undef, $inWeb, $inTopic, undef);
		die "no permissions!" unless $bool;
	}
	my $Transactions = Foswiki::UI::Accounting::getTable('Transactions');
	my $insert_statement = qq/INSERT INTO $Transactions ("key",post_date,enter_date) VALUES (?,?,?);/;
	my $insert_handler = $handler->database_connection()->prepare($insert_statement);
	$insert_handler->execute($key,$post_date,$enter_date);
	return $this->key;
}

1;
__END__

---+ debit/credit history of a single account
SELECT 
  s1.accounts_key, 
  s1.amount, 
  t1.enter_date, 
  t1.balance_checker
FROM 
  accounts."Transactions" t1, 
  accounts."Splits" s1
WHERE 
  t1."key" = s1.transaction_key AND
  s1.accounts_key = '30926f74-bd51-4daa-b028-df9bd5d9ea71'

---+ balance of single account
SELECT 
  s1.accounts_key, 
  SUM(s1.amount)
FROM 
  accounts."Splits" s1
WHERE 
  s1.accounts_key = '30926f74-bd51-4daa-b028-df9bd5d9ea71'
GROUP BY
  s1.accounts_key
  
---+ get transaction history of an account
SELECT 
  s1.accounts_key, 
  s1.amount, 
  t1.enter_date, 
  t1.balance_checker
FROM 
  accounts."Transactions" t1 
	INNER JOIN accounts."Splits" s1 ON s1.transaction_key = t1."key",
  accounts."Splits" s2
WHERE
  t1."key" = s2.transaction_key AND 
  s2.accounts_key = '30926f74-bd51-4daa-b028-df9bd5d9ea71'
---+ get account topic with parent key
SELECT 
  w1.current_web_name AS web_name, 
  tname."value" AS topic_name, 
  l1.destination_topic AS parent_key
FROM 
  foswiki."Topics" t1
	INNER JOIN foswiki."Blob_Store" tname ON t1.current_topic_name = tname."key"
	INNER JOIN foswiki."Webs" w1 ON t1.current_web_key = w1."key"
	INNER JOIN foswiki."Links" l1 ON t1.link_to_latest = l1.topic_history_key AND l1.link_type = 'PARENT',
  foswiki."Sites" s1
WHERE 
  s1.current_site_name = 'tokyo.e-flamingo.net' AND
  w1.current_web_name = 'AccountingJapan' AND
  tname."value" = 'TopAsset';
---+ Recursive Queries
WITH RECURSIVE parent_topic(web_name, topic_name, topic_key, parent_key, dummy) AS (

SELECT 
  w1.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t1."key" AS topic_key,
  l1.destination_topic AS parent_key,
  1 as dummy
FROM 
  foswiki."Topics" t1
	INNER JOIN foswiki."Blob_Store" tname ON t1.current_topic_name = tname."key"
	INNER JOIN foswiki."Webs" w1 ON t1.current_web_key = w1."key"
	INNER JOIN foswiki."Links" l1 ON t1.link_to_latest = l1.topic_history_key AND l1.link_type = 'PARENT',
  foswiki."Sites" s1
WHERE 
  s1.current_site_name = 'tokyo.e-flamingo.net' AND
  w1.current_web_name = 'AccountingJapan' AND
  tname."value" = 'JPYCash'

UNION

SELECT 
  w2.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t2."key" AS topic_key,
  l2.destination_topic AS parent_key,
  1 as dummy
FROM 
  foswiki."Topics" t2
	INNER JOIN foswiki."Blob_Store" tname ON t2.current_topic_name = tname."key"
	INNER JOIN foswiki."Webs" w2 ON t2.current_web_key = w2."key"
	INNER JOIN foswiki."Links" l2 ON t2.link_to_latest = l2.topic_history_key AND l2.link_type = 'PARENT',
  foswiki."Sites" s2, parent_topic
WHERE
  parent_topic.topic_key = l2.destination_topic

)
SELECT 
	--sp1.amount, parent_topic.web_name, parent_topic.topic_name
	SUM(sp1.amount)
FROM 
	parent_topic, accounts."Splits" sp1
WHERE
	parent_topic.topic_key = sp1.accounts_key
GROUP BY
	parent_topic.dummy;

---++ with levels N
   * note: there is a saftey level max of 100

WITH RECURSIVE parent_topic(web_name, topic_name, topic_key, parent_key, dummy, levels) AS (

SELECT 
  w1.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t1."key" AS topic_key,
  l1.destination_topic AS parent_key,
  1 as dummy,
  0 as levels
FROM 
  foswiki."Topics" t1
	INNER JOIN foswiki."Blob_Store" tname ON t1.current_topic_name = tname."key"
	INNER JOIN foswiki."Webs" w1 ON t1.current_web_key = w1."key"
	INNER JOIN foswiki."Links" l1 ON t1.link_to_latest = l1.topic_history_key AND l1.link_type = 'PARENT',
  foswiki."Sites" s1
WHERE 
  s1.current_site_name = 'tokyo.e-flamingo.net' AND
  w1.current_web_name = 'AccountingJapan' AND
  tname."value" = 'PaypalJPY20111026'

UNION

SELECT 
  w2.current_web_name AS web_name, 
  tname."value" AS topic_name,
  t2."key" AS topic_key,
  l2.destination_topic AS parent_key,
  1 as dummy,
  1 + parent_topic.levels
FROM 
  foswiki."Topics" t2
	INNER JOIN foswiki."Blob_Store" tname ON t2.current_topic_name = tname."key"
	INNER JOIN foswiki."Webs" w2 ON t2.current_web_key = w2."key"
	INNER JOIN foswiki."Links" l2 ON t2.link_to_latest = l2.topic_history_key AND l2.link_type = 'PARENT',
  foswiki."Sites" s2, parent_topic
WHERE
  parent_topic.topic_key = l2.destination_topic AND
  levels < N + 1

)
SELECT 
	--sp1.amount, parent_topic.web_name, parent_topic.topic_name
	SUM(sp1.amount)
FROM 
	parent_topic, accounts."Splits" sp1
WHERE
	parent_topic.topic_key = sp1.accounts_key
GROUP BY
	parent_topic.dummy;
	
---+ Split Trigger (for Links)
---++ Catching Up
INSERT INTO foswiki."Links" ("key",topic_history_key,destination_topic, link_type)

SELECT 
  foswiki.sha1_uuid(th1."key"::text || sp1.accounts_key::text || 'SPLIT') as "key",
  th1."key" as topic_history_key,
  sp1.accounts_key as destination_topic, 
  'SPLIT' as link_type
  
FROM 
  accounts."Transactions" tr1
	INNER JOIN accounts."Splits" sp1 ON tr1."key" = sp1.transaction_key
	INNER JOIN foswiki."Topic_History" th1 ON tr1."key" = th1.topic_key
;

---++ Trigger
