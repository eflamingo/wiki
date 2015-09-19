package Foswiki::Plugins::AccountsPlugin::Dwolla;

use strict;
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64 );
use Digest::SHA qw(hmac_sha1_hex);

# create a new Dwolla Object (only represents 1 order)
sub new {
	my $class = shift;
	my $order_obj = shift;	
	my $this;
	
	$this->{order} = $order_obj;
		
	bless $this, $class;
	
	return $this;
}
=pod
---+ Getters and Setters

=cut

sub order {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{order} = $x;
		return $this->{order};
	}
	else{
		return $this->{order};
	}
}

sub order_id {
	my $this = shift;
	return $this->order->key;
}

sub dwolla_id {
	my $this = shift;
	return '812-529-5755';
}

sub consumer_key {
	my $this = shift;
	
	return '5y/7GCm91OeitWKXzVtsyHzr0AVQZPi4pj/klkh0XEf80soUDp';
}

sub consumer_secret {
	my $this = shift;
	return 'MRoLYGtLongciJT6fFmwlsWv7N51JjzIVZ4fMrNz2qGLej6b5F';
}

sub timestamp_epoch {
	my $this = shift;
	return $this->order->post_date;
}

sub callback {
	my $this = shift;
	my $url = 'https://e-flamingo.net';
	# callback to /bin/accounts/Main/Order32423kf32N3
	# we need the WebName and TopicName of the order topic
	my ($rweb,$rtopic) = ($this->order->invoice_meta->web,$this->order->invoice_meta->topic);
	$url .= '/bin/accounts/'.$rweb.'/'.$rtopic.'?action=dwollaCallBack';
	return $url;
}

sub redirect {
	my $this = shift;
	my $url = 'https://e-flamingo.net';
	# redirect to /bin/view/Main/Order32423kf32N3
	$url .= '/bin/view/Main/ShoppingCenter';
	return $url;
}

sub amount {
	my $this = shift;
	my $amount = 0.00;

	# get amount from product page (time dependent, so we need the revision too)
	my $order_obj = $this->order;
	my $handler = $order_obj->handler;
	my ($pw1,$pt1,$rev1) = $handler->LoadWTRFromTHKey($order_obj->product_topic);
	my $productTopic = Foswiki::Meta::->new($Foswiki::Plugins::SESSION,$pw1,$pt1);
	$productTopic->load($rev1);
	my @fields = $productTopic->find('FIELD');
	my %fd1_form_hash;
	foreach my $fd1 (@fields) {
		$fd1_form_hash{$fd1->{'name'}} = $fd1->{'value'};
	}
	# figure out the amount, must be dollars to work with Dwolla
	my $currency;
	if($fd1_form_hash{'USD'}){
		$amount = $fd1_form_hash{'USD'};
	}
	else{
		$amount = 0;
	}
		
	return $amount;
}

# this is needed for the signature function (to do the hmac-sha1)
sub hex2bin {
        my $h = shift;
        my $hlen = length($h);
        my $blen = $hlen * 4;
        return unpack("B$blen", pack("H$hlen", $h));
}
# Generating the Signature (consumerKey + "&" + timestamp + "&" + orderId)
sub signature {
	my $this = shift;
	
	my $textToEncode = $this->consumer_key.'&'.$this->timestamp_epoch.'&'.$this->order_id;
	return undef unless $this->consumer_secret && $this->consumer_key && $this->timestamp_epoch && $this->order_id;
	
	my $hmac_result = hmac_sha1_hex($textToEncode, $this->consumer_secret );
	
	return $hmac_result;
}


=pod
---+ Pay Button
Using https://www.dwolla.com/developers/offsitegateway as a reference to construct a simple HTML gateway.
   * User ID of dejesus.joel is 812-529-5755
   * Consumer Key is 5y/7GCm91OeitWKXzVtsyHzr0AVQZPi4pj/klkh0XEf80soUDp
=cut
sub form_html {
	my $this = shift;
	# get the consumer key
	my $consumer_key_html = '<input id="key" name="key" type="hidden" value="'.$this->consumer_key.'" />';
	# get the dwolla_id
	my $dwolla_id_html = '<input id="destinationid" name="destinationid" type="hidden" value="'.$this->dwolla_id.'" />';
	# do the callback to the order topic page
	my $callback_html = '<input id="callback" name="callback" type="hidden" value="'.$this->callback.'" />';
	# Generating the Signature (consumerKey + "&" + timestamp + "&" + orderId)
	my $signature_html = '<input id="signature" name="signature" type="hidden" value="'.$this->signature.'" />';
	# generate the redirect html
	my $redirect_html = '<input id="redirect" name="redirect" type="hidden" value="'.$this->redirect.'" />';
	# generate the order_id html
	my $order_html = '<input id="orderid" name="orderid" type="hidden" value="'.$this->order_id.'" />';
	# use the post date as the timestamp for the dwolla order, since the postdate does not change
	my $timestamp_html = '<input id="timestamp" name="timestamp" type="hidden" value="'.$this->timestamp_epoch.'" />';	
	# generate the amount due, must make sure that the amount due is above zero and is denominated in dollars
	my $amount_html = '<input id="amount" name="amount" type="hidden" value="'.$this->amount.'" />';
	
	
	# Generate the HTML
	my $html = qq^
<form accept-charset="UTF-8" action="https://www.dwolla.com/payment/pay" method="post">
  $consumer_key_html
  $signature_html
  $callback_html
  $redirect_html
  <input id="test" name="test" type="hidden" value="true" />
  <input id="name" name="name" type="hidden" value="Gift Card Purchase" />
  <input id="description" name="description" type="hidden" value="Giftcard in Dollars" />
  $dwolla_id_html
  $amount_html
  <input id="shipping" name="shipping" type="hidden" value="0.00" />
  <input id="tax" name="tax" type="hidden" value="0.00" />
  $order_html
  $timestamp_html
  <button type="submit">Submit Order to Dwolla</button>
</form>
^;
	return $html;
}

1;