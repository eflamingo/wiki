package Foswiki::Plugins::FreeswitchPlugin::Domain;

use strict;
use warnings;


use Assert;
use Foswiki::Plugins::FreeswitchPlugin::Handler ();
# let us define some response xml


# DomainHandler::->new($domain_name)->$responsexml for domain section
sub new {
	my $class = shift;
	my $domain_name = shift;
	my $handler = shift;
	my $this;
	
	$this->{handler} = $handler;
	$this->{domain_name} = $domain_name;
	$this->{groups} = {};
	$this->{users} = {};
	$this->{context} = undef;
	bless $this, $class;
	$this->_getDialPlanKeyByDomain();
	$this->_fetchDefaultParameters();
	$this->_fetchDefaultVariables();
	return $this;
}

sub context {
	my $this = shift;
	my $context = shift;
	if($context){
		$this->{context} = $context;
		return $this->{context};
	}
	else{
		return $this->{context};
	}
}
#

# ()-> \@Parameters where %parameter = ( 'dial-string' => 'blah'); 
sub _fetchDefaultParameters{
	my $this = shift;
	my $handler = $this->{handler};
	$this->{parameters}->{'dial-string'} = '{presence_id=${dialed_user}@${dialed_domain}}${sofia_contact(${dialed_user}@${dialed_domain})}';
	#$this->{parameters}->{'context'} = $this->{context};
}

# ()-> \@Variables where %variable  = ( name => 'dial-string', value => 'blah');
sub _fetchDefaultVariables{
	my $this = shift;
	my $handler = $this->{handler};
	# list some default variables
	my @defaultVars;
	$this->{variables}->{'record_stereo'} = 'true';
	$this->{variables}->{'default_gateway'} = '$${default_provider}';
	$this->{variables}->{'default_areacode'} = '$${default_areacode}';
	$this->{variables}->{'transfer_fallback_extension'} = 'operator';
	# put the user_key as the context
	$this->{variables}->{'user_context'} = $this->{context};
}

sub _getDialPlanKeyByDomain {
	my $this = shift;
	my $handler = $this->{handler};
	my $domain_name = $this->{domain_name};
	
	my $DPF = $handler->getTable('DialPlan_Finder');
	my $selectStatement = qq/SELECT "value", level FROM $DPF WHERE domain = ? AND "name" = ? /; # 1-domain_name, 2- INTERNAL_DIALPLAN
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($domain_name,'INTERNAL_DIALPLAN');
	my ($dialplan_key,$level);
	$selectHandler->bind_col( 1, \$dialplan_key );
	$selectHandler->bind_col( 2, \$level );
	my @return_array;
	my ($LocalOrDefault,$context);
	while ($selectHandler->fetch) {
		$LocalOrDefault->{$level} = $dialplan_key;
		$context = $LocalOrDefault->{$level} if $level eq 'local';
	}
	$context = $LocalOrDefault->{'default'} unless $context;
	
	$this->{context} = $context;
}


sub setVariable {
	my $this = shift;
	my ($name,$value) = @_;
	$this->{variables}->{$name} = $value;
}
sub setParameter {
	my $this = shift;
	my ($name,$value) = @_;
	$this->{parameters}->{$name} = $value;
}
sub getVariable {
	my $this = shift;
	my $name = shift;
	return $this->{variables}->{$name};
}
sub getParameter {
	my $this = shift;
	my $name = shift;
	return $this->{parameters}->{$name};
}
# ($group_name,\@users)-> cache
sub setGroup {
	my $this = shift;
	# this is the group_key in Foswiki, not the Topic name of the group topic!
	my $group_name = shift;
	my $user_ref = shift;
	$this->{groups}->{$group_name} = $user_ref;
}

sub setLocalPrefs {
	my $this = shift;
	my $pref_key = shift;
	$this->{local_preferences} = $pref_key;
}
sub setDefaultPrefs {
	my $this = shift;
	my $pref_key = shift;
	$this->{default_preferences} = $pref_key;
}
# ($user_obj)-> adds user obj to cache
sub addUser {
	my $this = shift;
	my $user_obj = shift;
	my $login_name = $user_obj->login_name();
	$this->{users}->{$login_name} = $user_obj;
}
##########################    Printing Functions     #################################
sub _print_params {
	my $this = shift;
	my @params = keys %{$this->{parameters}};
	my $return_string = '';
	my @paramXML;
	foreach my $name (@params) {
		push(@paramXML, '<param name="'.$name.'" value="'.$this->getParameter($name).'"/>') if $this->getParameter($name);
	}
	unless(scalar(@paramXML) == 0){
		$return_string = join(' ',@paramXML);
		$return_string = '<params>'.$return_string.'</params>';
	}
	return $return_string;
}
sub _print_vars {
	my $this = shift;
	my @variables = keys %{$this->{variables}};
	my $return_string = '';
	my @varXML;
	foreach my $name (@variables) {
		push(@varXML, '<variable name="'.$name.'" value="'.$this->getVariable($name).'"/>') if $this->getVariable($name);
	}
	unless(scalar(@varXML) == 0) {
		$return_string = join(' ',@varXML);
		$return_string = '<variables>'.$return_string.'</variables>';	
	}
	
	return $return_string;
}
# <user id="phone-tokyo001" type="pointer"/>
sub _print_groups {
	my $this = shift;
	my @groups = keys %{$this->{groups}};
	my $return_string = '';
	my @groupXML;
	foreach my $group_name (@groups) {
		my @userXML;
		foreach my $login_name (@{$this->{groups}->{$group_name}}){
			push(@userXML, '<user id="'.$login_name.'" type="pointer"/>');
		}
		push(@groupXML,'<group name="'.$group_name.'">'.join(' ',@userXML).'</group>') if scalar(@userXML) > 0;
	}
	unless(scalar(@groupXML) == 0){
		$return_string = join(' ',@groupXML);
		$return_string = '<groups>'.$return_string.'</groups>';
	}
	return $return_string;
}
sub _print_users {
	my $this = shift;
	my @users = keys %{$this->{users}};
	my $return_string = '';
	my @userXML;
	foreach my $login_name (@users) {
		push(@userXML,$this->{users}->{$login_name}->print_user() );
	}
	unless(scalar(@userXML) == 0) {
		$return_string = join(' ',@userXML);
		$return_string = '<groups><group name="default"><users>'.$return_string.'</users></group></groups>';
		#$return_string = '<users>'.$return_string.'</users>';	
	}
	return $return_string;
}
sub print_domain {
	my $this = shift;
	my $params = $this->_print_params();
	my $vars = $this->_print_vars();
	my $groups = $this->_print_groups();
	my $users = $this->_print_users();
	my $domain_name = $this->{domain_name};
	
	my $return_string = $params.' '.$vars.' '.$groups.' '.$users;
	$return_string = '<domain name="'.$domain_name.'" >'.$return_string.'</domain>';
}



1;
__END__

share.elmo @ tokyo.e-flamingo.net
1b20353b-3366-4957-884e-cafce1b48b91

=pod
        <params>
          <param name="dial-string" value="{presence_id=${dialed_user}@${dialed_domain}}${sofia_contact(${dialed_user}@${dialed_domain})}"/>
        </params>

        <variables>
          <variable name="record_stereo" value="true"/>
          <variable name="default_gateway" value="$${default_provider}"/>
          <variable name="default_areacode" value="$${default_areacode}"/>
          <variable name="transfer_fallback_extension" value="operator"/>
          <variable name="user_context" value="e-flamingo.jp"/>
        </variables>
=cut
