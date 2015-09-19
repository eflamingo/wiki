# See bottom of file for license and copyright information

=pod TML

---+ package Foswiki::UI::Sip

User registration handling.

=cut

package Foswiki::UI::Sip;

use strict;
use warnings;
use Assert;
use Error qw( :try );
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Data::Dump qw(dump); # I prefer this to Data::Dumper
use Foswiki                ();
use Foswiki::OopsException ();
use Foswiki::Sandbox       ();
use Foswiki::UI            ();
use Foswiki::Contrib::DBIStoreContrib::UserHandler ();
use Foswiki::Plugins::FreeswitchPlugin::Handler;
use Foswiki::Plugins::FreeswitchPlugin::Domain;

BEGIN {

    # Do a dynamic 'use locale' for this module
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

=pod TML

---++ StaticMethod register_user( $session )

=register_user= command handler.
This method is designed to be
invoked via the =UI::run= method.

Generate xml for Freeswitch to munch on.
If a user is not found, then 404 the request.
---++ Public Data members of the Session Object
   * =request=          Pointer to the Foswiki::Request
   * =response=         Pointer to the Foswiki::Response
   * =context=          Hash of context ids
   * =plugins=          Foswiki::Plugins singleton
   * =prefs=            Foswiki::Prefs singleton
   * =remoteUser=       Login ID when using ApacheLogin. Maintained for
                        compatibility only, do not use.
   * =requestedWebName= Name of web found in URL path or =web= URL parameter
   * =scriptUrlPath=    URL path to the current script. May be dynamically
                        extracted from the URL path if {GetScriptUrlFromCgi}.
                        Only required to support {GetScriptUrlFromCgi} and
                        not consistently used. Avoid.
   * =security=         Foswiki::Access singleton
   * =store=            Foswiki::Store singleton
   * =topicName=        Name of topic found in URL path or =topic= URL
                        parameter
   * =urlHost=          Host part of the URL (including the protocol)
                        determined during intialisation and defaulting to
                        {DefaultUrlHost}
   * =user=             Unique user ID of logged-in user
   * =users=            Foswiki::Users singleton
   * =webName=          Name of web found in URL path, or =web= URL parameter,
                        or {UsersWebName}
=cut

sub sip {
	my $session = shift;
	my $request = $session->{request};
	my $binding = $request->param('section');
	my $cdr = $request->param('cdr');
	my $uri = $request->url([query   => 1]);
	
	my $return_xml = '';
	my $handler;
	
	if($binding eq 'configuration'){
		# load sofia configuration
		# let freeswitch load it from the xml files, not foswiki

		my $module_config = $request->param('key_value');
		if($module_config eq 'sofia.conf_nothing...'){
			# fetch all of the gateways
			$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
			# get the main sofia profile
			open(FILE, "</var/www/wiki/core/lib/Foswiki/Plugins/FreeswitchPlugin/sofia-profile.xml") or die("Unable to open file");
			my @sofiaprofile = <FILE>;
			close(FILE);
			# get the external profile
			open(FILE, "</var/www/wiki/core/lib/Foswiki/Plugins/FreeswitchPlugin/sofia-profile-external.xml") or die("Unable to open file");
			my @externalprofile = <FILE>;
			close(FILE);
			# get the internal profile
			open(FILE, "</var/www/wiki/core/lib/Foswiki/Plugins/FreeswitchPlugin/sofia-profile-internal.xml") or die("Unable to open file");
			my @internalprofile = <FILE>;
			close(FILE);			
			
			# get the gateways
			my %gateways = %{$handler->fetch_gateways()};
			# print the gateways
			my $gatewayXML = ' ';
			foreach my $gy (keys %gateways){
				$gatewayXML .= $gateways{$gy}->print_gateway();
			}
			
			foreach my $line (@sofiaprofile){
				# load the external profile with the gateways then internal profile
				if($line =~ /    <X-PRE-PROCESS cmd="include" data="..\/sip_profiles\/*.xml"\/>/){
					# internal profile
					$return_xml .= join("\n",@internalprofile);	
					# external profile, where the gateways are
					foreach my $exline (@externalprofile){
						if($exline eq '    <!--<X-PRE-PROCESS cmd="include" data="external/*.xml"/>-->'){
							$return_xml .= $gatewayXML;
						}
						else{
							$return_xml .= "\n".$exline;
						}
					}
				}
				else{
					$return_xml .= $line;
				}
			} 
					
		}
	}
	elsif($binding eq 'directory'){
		# connect to the super awesome database
		
		# delete the next line after testing
		
		# mod_sofia start up
		# get variables needed to figure out what to respond with
		my $purpose = $request->param('purpose');
		my $profile = $request->param('sip_profile');
		my $acl = $request->param('network-list');		
		my $action = $request->param('action');
		my $user_id = $request->param('user');
		my $domain_name = $request->param('domain');
		my $hostname = $request->param('hostname');
		
		
		# get gateways
		if($purpose eq 'gateways'){
			# Startup
			# http://wiki.freeswitch.org/wiki/Mod_xml_curl#Startup
			# Give freeswitch all of the domains
			$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
			$handler->fetch_domains();
			
			# print all of the domains
			$return_xml = $handler->print_directory();
			#die "Gateways: $return_xml";
		}
		elsif($purpose eq 'network-list'){
			# ACL
			# http://wiki.freeswitch.org/wiki/Mod_xml_curl#ACL
			
		}
		elsif($action eq 'sip_auth'){
			# Authorization
			# http://wiki.freeswitch.org/wiki/Mod_xml_curl#Authorization

			if($request->param('tag_name') eq 'domain' && $request->param('key_name') eq 'name'
					&& $request->param('domain') eq $request->param('key_value') ){
				# get the user from the database
				$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
				$handler->fetchUser($domain_name,$user_id);
				# should only print 1 domain with 1 user
				$return_xml = $handler->print_directory();
			}
			else{
				# don't bother getting the user
				$return_xml = '';
			}		
			
		}
		elsif($action eq 'message-count'){
			# Voicemail Request
			# http://wiki.freeswitch.org/wiki/Mod_xml_curl#Voicemail_request
			
			# do the samething as in authorization
			if($request->param('tag_name') eq 'domain' && $request->param('key_name') eq 'name'
					&& $request->param('domain') eq $request->param('key_value') ){
				# get the user from the database
				$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
				$handler->fetchUser($domain_name,$user_id);
				# should only print 1 domain with 1 user
				$return_xml = $handler->print_directory();
			}
			else{
				# don't bother getting the user
				$return_xml = '';
			}	
		}
		elsif($user_id && $domain_name && $hostname){
			# freeswitch queries stuff from time to time
			$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
			$handler->fetchUser($domain_name,$user_id);
			# should only print 1 domain with 1 user
			$return_xml = $handler->print_directory();
		}
		elsif($domain_name){
			# just get the domain only
			$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
			$handler->getOneDomain($domain_name);
			$return_xml = $handler->print_directory();
			
		}

	}
	elsif($binding eq 'dialplan'){
		
		my $user_id = $request->param('variable_user_name');
		my $dial_plan_key = $request->param('variable_user_context');
		my $destination_number = $request->param('Hunt-Destination-Number');
		my $from_ip = $request->param('variable_sip_from_host');
		# if it is a public call
		$dial_plan_key = $request->param('Hunt-Context') unless $dial_plan_key && $dial_plan_key ne 'public';
		
		$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
		#my $crap = _generateParams($request);
		#die "Crap: $crap";
		
		$return_xml = $handler->getExtension({'dial_plan_key' => $dial_plan_key, 'destination_number' => $destination_number, 'variable_sip_from_host' => $from_ip});

	}
	elsif(!$binding && $cdr){
		$handler = Foswiki::Plugins::FreeswitchPlugin::Handler::->new($session);
		# cdr in put
		require Foswiki::Plugins::FreeswitchPlugin::CDR;
		my $cdr_obj = Foswiki::Plugins::FreeswitchPlugin::CDR::->new($cdr,$handler);
		my $success_bool = $cdr_obj->save; 
		if($success_bool){
			# was success ful
		}
		else{
			# do nothing
			my $error_msg = $cdr_obj->save_error;
			print $error_msg;
		}
		
	}
	unless($return_xml){
		# return 404 msg saying nothing was found
		$return_xml = _return404Error();
		#$return_xml = _generateParams($request);
		#die "Returned: \n\n$return_xml";
	}

	# let's generate the XML page
	$session->generateHTTPHeaders( 'view', 'text/xml', $return_xml, undef );
	$session->{response}->print($return_xml);
}


# this is the standard 404 error message
sub _return404Error {
	my $ErrorMsg = qq^<?xml version="1.0" encoding="UTF-8" standalone="no"?>
		<document type="freeswitch/xml">
		  <section name="result">
		    <result status="not found" />
		  </section>
		</document>^;
	return $ErrorMsg;
}


sub _startNewdbiconnection {
	require Foswiki::Plugins::FreeswitchPlugin::Handler;
	return Foswiki::Plugins::FreeswitchPlugin::Handler::->new();
}


# for error checking
sub _generateParams {
	my $request = shift;

	my @params = $request->param;
			
	my @return_XML;
	my $sinner;
	foreach my $param (@params){
		my $crap = $request->param($param);
		$sinner .= "\n$param = $crap";
		push(@return_XML,$param.'='.$request->param($param));
	}
	#return join('&',@return_XML);
	return $sinner;
	
}


1;
__END__

startup->
?hostname=testmachine&section=directory&tag_name=&key_name=&key_value=&Event-Name=REQUEST_PARAMS&Core-UUID=c5c8cbf4-60c3-45a2-b110-933da620cfd2&FreeSWITCH-Hostname=testmachine&
FreeSWITCH-IPv4=192.168.1.10&FreeSWITCH-IPv6=::1&Event-Date-Local=2009-10-27 00:52:52&Event-Date-GMT=Tue, 27 Oct 2009 07:52:52 GMT&Event-Date-Timestamp=1256629972839876&
Event-Calling-File=sofia.c&Event-Calling-Function=config_sofia&Event-Calling-Line-Number=3056&purpose=gateways&profile=external


section=dialplan&tag_name=&key_name=&key_value=&context=default&destination_number=556
&caller_id_name=FreeSwitch&caller_id_number=5555551212&network_addr=&ani=&aniii=&rdnis=
&source=mod_portaudio&chan_name=PortAudio/556&uuid=b7f0b117-351f-9448-b60a-18ff91cbe183
&endpoint_disposition=ANSWER





