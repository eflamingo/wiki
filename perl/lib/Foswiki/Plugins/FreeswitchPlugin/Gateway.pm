package Foswiki::Plugins::FreeswitchPlugin::Gateway;

use strict;
use warnings;


use Assert;

# let us define some response xml


# Gateway::->new($domain_name)->$responsexml for domain section
sub new {
	my $class = shift;
	my $xmlname = shift;
	my $this = {'xmlname' => ' '};
	bless $this, $class;	
	$this->xmlname($xmlname);
	return $this;
}

############ Define the getters and setters ########### 
# type defines which provider this gateway is for
sub type {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{type} = $x;
		return $this->{type};
	}
	else{
		return $this->{type};
	}
}

sub xmlname {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{xmlname} = $x;
		return $this->{xmlname};
	}
	else{
		return $this->{xmlname};
	}
}

sub full_number {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{full_number} = $x;
		return $this->{full_number};
	}
	else{
		return $this->{full_number};
	}
}

sub username {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{username} = $x;
		return $this->{username};
	}
	else{
		return $this->{username};
	}
}

sub password {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{password} = $x;
		return $this->{password};
	}
	else{
		return $this->{password};
	}
}
# ('realm') -> return realm, ('realm', 'e-flamingo.net') -> sets realm to e-flamingo.net
# () -> @parameter_names
sub parameter {
	my $this = shift;
	my $x = shift;
	my $y = shift;
	if($x && $y){
		$this->{parameter}->{$x} = $y;
		return $this->{parameter}->{$x};
	}
	elsif($x){
		return $this->{parameter}->{$x};
	}
	else{
		return keys %{$this->{parameter}};
	}
}
###################################################################


# if this is a fusion gateway, set the following parameters
sub _set_fusion {
	my $this = shift;
	
}

# print the gateway xml 
sub print_gateway {
	my $this = shift;
	my $xmlreturn = ' ';

	foreach my $param_name ($this->parameter()){
		$xmlreturn .= '<param name="'.$param_name.'" value="'.$this->parameter($param_name).'" />';
	}
	$xmlreturn = '<gateway name="'.$this->xmlname.'">'.$xmlreturn.'</gateway>';
	return $xmlreturn;
}

################ Set the Parameters based on the Username, password, and type ###########
sub set_parameters {
	my $this = shift;
	$this->_set_fusion_parameters() if $this->type eq 'fusion';
	$this->_set_agile_ne_jp_parameters() if $this->type eq 'agile_ne_jp';
	$this->_set_icall_domestic_parameters() if $this->type eq 'icall_domestic';
	$this->_set_icall_international_parameters() if $this->type eq 'icall_international';
}

sub _set_fusion_parameters {
	my $this = shift;
	# user names have to be fetched from the db
	# so the usernames and passwords should already be defined
	# add the parameters
	$this->parameter('username',$this->username);
	$this->parameter('from-user',$this->username);
	$this->parameter('password',$this->password);
	$this->parameter('from-domain','kwus.sip.0038.net');
	$this->parameter('proxy','kwus.sip.0038.net');
	$this->parameter('realm','kwus.sip.0038.net');
	$this->parameter('sip-port','5060');
	$this->parameter('ping','30');
	$this->parameter('expire-seconds','3600');
	$this->parameter('retry-seconds','60');
	$this->parameter('register','true');
	$this->parameter('codec-prefs','PCMU');
	$this->parameter('inbound-codec-prefs','PCMU');
	$this->parameter('outbound-codec-prefs','PCMU');
	$this->parameter('codec-ms','20');

}

sub _set_agile_ne_jp_parameters {
	my $this = shift;
	$this->username('0000202962');
	$this->password('cow3TurtleP96');
		# add the parameters
	$this->parameter('username',$this->username);
	$this->parameter('from-user',$this->username);
	$this->parameter('password',$this->password);
	$this->parameter('from-domain','kwus.sip.0038.net');
	$this->parameter('proxy','voip3017.agile.ne.jp');
	$this->parameter('realm','voip3017.agile.ne.jp');
	$this->parameter('sip-port','5060');
	$this->parameter('ping','30');
	$this->parameter('expire-seconds','3600');
	$this->parameter('retry-seconds','60');
	$this->parameter('register','true');
	$this->parameter('codec-prefs','PCMU');
	$this->parameter('inbound-codec-prefs','PCMU');
	$this->parameter('outbound-codec-prefs','PCMU');
	$this->parameter('codec-ms','20');

}

sub _set_icall_domestic_parameters {
	my $this = shift;
		# add the parameters
	$this->username('cust_slopyjalopi_vps-linode02');
	$this->password('kawaningyoumono6698');
	$this->parameter('username',$this->username);
	$this->parameter('from-user',$this->username);
	$this->parameter('password',$this->password);
	$this->parameter('from-domain','kwus.sip.0038.net');
	$this->parameter('proxy','voip3017.agile.ne.jp');
	$this->parameter('realm','voip3017.agile.ne.jp');
	$this->parameter('sip-port','5060');
	$this->parameter('ping','30');
	$this->parameter('expire-seconds','3600');
	$this->parameter('retry-seconds','60');
	$this->parameter('register','true');
	$this->parameter('codec-prefs','PCMU');
	$this->parameter('inbound-codec-prefs','PCMU');
	$this->parameter('outbound-codec-prefs','PCMU');
	$this->parameter('codec-ms','20');

}

sub _set_icall_international_parameters {
	my $this = shift;
		# add the parameters
	$this->username('cust_slopyjalopi_vps-linode02');
	$this->password('kawaningyoumono6698');
	$this->parameter('username',$this->username);
	$this->parameter('from-user',$this->username);
	$this->parameter('password',$this->password);
	$this->parameter('from-domain','kwus.sip.0038.net');
	$this->parameter('proxy','voip3017.agile.ne.jp');
	$this->parameter('realm','voip3017.agile.ne.jp');
	$this->parameter('sip-port','5060');
	$this->parameter('ping','30');
	$this->parameter('expire-seconds','3600');
	$this->parameter('retry-seconds','60');
	$this->parameter('register','true');
	$this->parameter('codec-prefs','PCMU');
	$this->parameter('inbound-codec-prefs','PCMU');
	$this->parameter('outbound-codec-prefs','PCMU');
	$this->parameter('codec-ms','20');

}


1;

__END__
  <gateway name="icall">
    <!-- Replace these value with your iCall Carrier Services username and password. -->
    <!-- Even if you use an IP-based sub-account, FreeSWITCH needs these values -->
    <param name="username" value="cust_slopyjalopi_vps-linode02" />
    <param name="password" value="kawaningyoumono6698" />
    <param name="from-user" value="cust_slopyjalopi_vps-linode02" />
    <param name="proxy" value="sbc01-car.dal.us.icall.net" />
    <param name="realm" value="sbc01-car.dal.us.icall.net" />
    <param name="ping" value="30" /> 
    <param name="expire-seconds" value="600"/>
    <!-- Set to "false" for IP-based accounts, or "true" for registration based -->
    <param name="register" value="true" />
  </gateway>
  <gateway name="icall_international">
    <!-- Replace these value with your iCall Carrier Services username and password. -->
    <!-- Even if you use an IP-based sub-account, FreeSWITCH needs these values -->
    <param name="username" value="cust_slopyjalopi_vps-linode02" />
    <param name="password" value="kawaningyoumono6698" />
    <param name="from-user" value="cust_slopyjalopi_vps-linode02" />
    <param name="proxy" value="gw01-car.dal.us.icall.net" />
    <param name="realm" value="gw01-car.dal.us.icall.net" />
    <!-- Set to "false" for IP-based accounts, or "true" for registration based -->
    <param name="register" value="true" />
    <param name="ping" value="30" /> 
    <param name="expire-seconds" value="600"/>
  </gateway>
        <gateway name="fusion">
                <param name="username" value="58303625" />
                <param name="from-user" value="58303625" />
                <param name="password" value="xv2u4EWD" />
                <param name="from-domain" value="kwus.sip.0038.net"/>
                <param name="proxy" value="kwus.sip.0038.net"/>
                <param name="realm" value="kwus.sip.0038.net" />
                <param name="sip-port" value="5060"/>
                <param name="ping" value="30" />
                <param name="expire-seconds" value="3600"/>
                <param name="retry-seconds" value="60"/>
                - Set to "false" for IP-based accounts, or "true" for registration based -
                <param name="register" value="true" />
                <param name="codec-prefs" value="PCMU"/>
                <param name="inbound-codec-prefs" value="PCMU"/>
                <param name="outbound-codec-prefs" value="PCMU"/>
                <param name="codec-ms" value="20"/>

        </gateway>

