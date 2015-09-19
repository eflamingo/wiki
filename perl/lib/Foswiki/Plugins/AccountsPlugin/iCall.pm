package Foswiki::Plugins::AccountsPlugin::iCall;

use strict;
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64 );
use Digest::SHA qw(hmac_sha1_hex);
use LWP::Simple();
use LWP 5.64;


=pod
---+ List of Area Code <==> Geographic Location mappings
=cut
my %code_list = ('205' => 'Alabama - Birmingham/Central Alabama','251' => 'Alabama','659' => 'Alabama','256' => 'Alabama - Huntsville/North Alabama','334' => 'Alabama - Montgomery/Mobile/Lower Alabama','907' => 'Alaska','403' => 'Alberta , Southern',
'587' => 'Alberta','587' => 'Alberta','780' => 'Alberta, Edmonton & North','684' => 'American Samoa','264' => 'Anguilla','268' => 'Antigua/Barbuda-Carib','520' => 'Arizona','928' => 'Arizona','480' => 'Arizona - Phoenix. East Valley','602' => 'Arizona - Phoenix','623' => 'Arizona - Phoenix. West Valley','501' => 'Arkansas','479' => 'Arkansas','870' => 'Arkansas','242' => 'Bahamas-Carib','246' => 'Barbados-Carib','441' => 'Bermuda-Carib','250' => 'British Columbia','604' => 'British Columbia','778' => 'British Columbia','284' => 'British V.I.-Carib','341' => 'California','442' => 'California','628' => 'California','657' => 'California','669' => 'California','747' => 'California','752' => 'California','764' => 'California','951' => 'California','209' => 'California - Central','559' => 'California - Central','408' => 'California - Central Coastal','831' => 'California - Central Coastal','510' => 'California - East Bay Area','213' => 'California - Los Angeles','310' => 'California - Los Angeles','424' => 'California - (overlay 310)','323' => 'California - Los Angeles','562' => 'California - Los Angeles','707' => 'California - North Coastal','369' => 'California - (split from 707)','627' => 'California - (split from 707)','530' => 'California - Northern','714' => 'California - Orange County','949' => 'California - Orange County','626' => 'California - Pas./San Gabr.Vly','909' => 'California - Riverside&S.Bern','916' => 'California - Sacramento','760' => 'California - San Diego','619' => 'California - San Diego, S.Cal','858' => 'California - (split from 619)','935' => 'California - (split from 619)','818' => 'California - SF Valley, LA area','415' => 'California - San Francisco','925' => 'California - S.F.Bay area','661' => 'California - (split from 805)','805' => 'California - SouthCentral','650' => 'California - West Bay Area','600' => 'Canada/Services','809' => 'Caribbean Islands','345' => 'Cayman Islands','670' => 'CNMI-Mariana Islands','211' => 'Coin Phone Refunds','720' => 'Colorado - Denver & suburban','970' => 'Colorado - Northern & Western','303' => 'Colorado - Denver & suburban','719' => 'Colorado - Southern & Eastern','203' => 'Connecticut','475' => 'Connecticut - (overlay 203)','860' => 'Connecticut','959' => 'Connecticut - (overlay 860)','302' => 'Delaware','411' => 'Directory Services','202' => 'District Of Columbia','767' => 'Dominica',
'829' => 'Dominican Republic','829' => 'Dominican Rep','911' => 'Emergency Services','239' => 'Florida - Naples/Ft. Myers','386' => 'Florida','689' => 'Florida','754' => 'Florida - Boca Raton/Lauderdale','941' => 'Florida - Bradenton/Sarasota','954' => 'Florida - Greater Ft Lauderdale','561' => 'Florida - Greater Palm Beach','407' => 'Florida - Greater Orlando','727' => 'Florida - Greater St Petersburg','352' => 'Florida - North','904' => 'Florida - Jacksonville','850' => 'Florida panhandle','786' => 'Florida - Overlay the 305 area','863' => 'Florida - South Central','305' => 'Florida - Miami/SE Florida','321' => 'Florida Space Coast (Melbourne)','813' => 'Florida - Tampa area','470' => 'Georgia','478' => 'Georgia','770' => 'Georgia','678' => 'Georgia','404' => 'Georgia - Metro Atlanta','706' => 'Georgia - Northern',
'762' => 'Georgia','912' => 'Georgia - Southern','229' => 'Georgia - (split from 912)','762' => 'Georgia','710' => 'Gov Emer Telecom Svc','473' => 'Grenada-Carib','671' => 'Guam','808' => 'Hawaii','208' => 'Idaho','312' => 'Illinois - Chicago','773' => 'Illinois - Chicago','630' => 'Illinois - Chicago suburbs','847' => 'Illinois - Chicago suburbs','708' => 'Illinois - NorthEast','815' => 'Illinois - Northern','224' => 'Illinois','331' => 'Illinois','464' => 'Illinois overlay deferred','872' => 'Illinois overlay deferred','217' => 'Illinois - South Central','618' => 'Illinois - Southern','779' => 'Illinois',
'779' => 'Illinois','309' => 'Illinois - West Central','260' => 'Indiana','317' => 'Indiana - Central','219' => 'Indiana - Northern','765' => 'Indiana - Outside Indianapolis','812' => 'Indiana - Southern','563' => 'Iowa','641' => 'Iowa','515' => 'Iowa - Central','319' => 'Iowa - Eastern','712' => 'Iowa - Western','876' => 'Jamaica','620' => 'Kansas - Southern','785' => 'Kansas - Northern','913' => 'Kansas - NorthEast','316' => 'Kansas-Wichita area','270' => 'Kentucky',
'364' => 'Kentucky','859' => 'Kentucky','606' => 'Kentucky - Eastern','502' => 'Kentucky - Western','364' => 'Kentucky','225' => 'Louisiana','337' => 'Louisiana','985' => 'Louisiana','504' => 'Louisiana - Eastern','318' => 'Louisiana - Western','207' => 'Maine','204' => 'Manitoba','227' => 'Maryland','240' => 'Maryland','443' => 'Maryland','667' => 'Maryland','410' => 'Maryland - Eastern','301' => 'Maryland - Southern&Western','339' => 'Massachusetts','351' => 'Massachusetts','774' => 'Massachusetts','781' => 'Massachusetts','857' => 'Massachusetts','978' => 'Massachusetts','508' => 'Massachusetts - Eastern','617' => 'Massachusetts - Eastern','413' => 'Massachusetts - Western','231' => 'Michigan','269' => 'Michigan','989' => 'Michigan','734' => 'Michigan - Ann Arbor/Ypsilanti','517' => 'Michigan - Central','313' => 'Michigan - Eastern','810' => 'Michigan - Northern','248' => 'Michigan - Oakland Cty','278' => 'Michigan overlay suspended','586' => 'Michigan overlay','679' => 'Michigan overlay suspended','947' => 'Michigan','906' => 'Michigan - Upper North','616' => 'Michigan - Western','320' => 'Minnesota','612' => 'Minnesota - Minneapolis','763' => 'Minnesota - Minneapolis Suburbs','952' => 'Minnesota - Minneapolis Suburbs','218' => 'Minnesota - Northern','507' => 'Minnesota - Southern','651' => 'Minnesota - St. Paul','769' => 'Mississippi','228' => 'Mississippi','601' => 'Mississippi',
'769' => 'Mississippi','557' => 'Missouri',

'573' => 'Missouri','636' => 'Missouri','660' => 'Missouri','975' => 'Missouri','314' => 'Missouri - Eastern','816' => 'Missouri - NorthWest','417' => 'Missouri - SouthWest','664' => 'Montserrat-Carib','406' => 'Montana','402' => 'Nebraska - Eastern','308' => 'Nebraska - Western','775' => 'Nevada','702' => 'Nevada - Clark County','506' => 'New Brunswick','603' => 'New Hampshire','551' => 'New Jersey','848' => 'New Jersey','862' => 'New Jersey','732' => 'New Jersey - Central','908' => 'New Jersey - Central','201' => 'New Jersey - NorthEast','973' => 'New Jersey - Northern','609' => 'New Jersey - Southern','856' => 'New Jersey - Southern','505' => 'New Mexico','575' => 'New Mexico','585' => 'New York','845' => 'New York','917' => 'New York City','516' => 'New York - Nassau County LI','212' => 'New York - Manhattan','646' => 'New York - Manhattan (split from 212)','315' => 'New York - North Central','518' => 'New York - NorthEast','347' => 'New York - NYC-not Mnhtn (split from 718)','718' => 'New York - NYC except Mnhtn','607' => 'New York - South Central','914' => 'New York - Southern','631' => 'New York - Suffolk County LI','716' => 'New York - Western','709' => 'Newfndlnd, Labradr','252' => 'North Carolina','336' => 'North Carolina','828' => 'North Carolina','910' => 'North Carolina','980' => 'North Carolina','984' => 'North Carolina','919' => 'North Carolina - Eastern','704' => 'North Carolina - Western','701' => 'North Dakota','283' => 'Ohio','380' => 'Ohio','567' => 'Ohio','216' => 'Ohio - Cleveland','614' => 'Ohio - Columbus Area','937' => 'Ohio - Dayton, SW Ohio','330' => 'Ohio - Eastern','234' => 'Ohio (overlay 330)','440' => 'Ohio - Northeast','419' => 'Ohio - NorthWest','740' => 'Ohio - SouthEast','513' => 'Ohio - SouthWest','580' => 'Oklahoma','918' => 'Oklahoma - NorthEast','405' => 'Oklahoma- Southern & Western','905' => 'Greater Toronto Area, except Toronto',
'226' => 'Ontario','289' => 'Ontario','647' => 'Ontario','705' => 'Ontario - Northern','807' => 'Ontario - NorthWest','613' => 'Ontario - SouthEast','519' => 'Ontario - SouthWest','416' => 'Ontario - City of Toronto','343' => 'Ontario','226' => 'Ontario','503' => 'Oregon - Portland tri-metro','541' => 'Oregon','971' => 'Oregon','458' => 'Oregon','445' => 'Pennsylvania','610' => 'Pennsylvania','835' => 'Pennsylvania','878' => 'Pennsylvania','484' => 'Pennsylvania (overlay 610)','717' => 'Pennsylvania - East Central','570' => 'Pennsylvania - (split 717)','412' => 'Pennsylvania - Pittsburgh','215' => 'Pennsylvania - SouthEast','267' => 'Pennsylvania (overlay 215)','814' => 'Pennsylvania - West Central','724' => 'Pennsylvania - Western','902' => 'Pr Edwrd Is, Nva Sctia','787' => 'Puerto Rico - Carib','939' => 'Puerto Rico','438' => 'Quebec','450' => 'Quebec-Laval (Montreal North)','819' => 'Quebec - Eastern','418' => 'Quebec - NorthEast','581' => 'Quebec','514' => 'Quebec, Montreal',
'581' => 'Quebec','401' => 'Rhode Island','306' => 'Saskatchewan','803' => 'South Carolina','843' => 'South Carolina','864' => 'South Carolina','605' => 'South Dakota','869' => 'St. Kitts and Nevis-Carib','758' => 'St. Lucia-Carib','784' => 'St. Vincent/Grenadines','731' => 'Tennessee','865' => 'Tennessee','931' => 'Tennessee','423' => 'Tennessee - Eastern','615' => 'Tennessee - Middle/Western','901' => 'Tennessee - Western','325' => 'Texas','361' => 'Texas - (split from 512)','430' => 'Texas','432' => 'Texas','469' => 'Texas','682' => 'Texas','737' => 'Texas','979' => 'Texas','214' => 'Texas - Dallas','972' => 'Texas - Dallas','254' => 'Texas - Ft. Worth','940' => 'Texas - Ft. Worth','713' => 'Texas - Houston','281' => 'Texas - Houston Area','832' => 'Texas - Houston area','956' => 'Texas - Laredo/Brownsville','817' => 'Texas - North Central','806' => 'Texas - North Panhandle','903' => 'Texas - NorthEast','210' => 'Texas - San Antonio','830' => 'Texas - South, near San Antonio','409' => 'Texas - SouthEast','936' => 'Texas - (split from 409)','512' => 'Texas - Southern','915' => 'Texas - Western','868' => 'Trinidad and Tobago-Carib','649' => 'Turks & Caicos','340' => 'US Virgin Islands','385' => 'Utah','435' => 'Utah','801' => 'Utah','802' => 'Vermont','276' => 'Virginia','434' => 'Virginia','540' => 'Virginia','571' => 'Virginia','757' => 'Virginia','703' => 'Virginia - Northern & Western','804' => 'Virginia - SouthEast','509' => 'Washington - Eastern','206' => 'Washington - Seattle','425' => 'Washington - Seattle east suburbs','253' => 'Washington - Tacoma','360' => 'Washington - Western','564' => 'Washington - (overlay 360)','304' => 'West Virginia',
'681' => 'West Virginia','262' => 'Wisconsin','920' => 'Wisconsin','414' => 'Wisconsin - Eastern','715' => 'Wisconsin - Northern','608' => 'Wisconsin - SouthWest','274' => 'Wisconsin','534' => 'Wisconsin','681' => 'Wisconsin','307' => 'Wyoming','867' => 'Yukon/N.W.Terr´s','822' => 'Future Toll-Free Svc.','833' => 'Future Toll-Free Svc.','844' => 'Future Toll-Free Svc.','855' => 'Future Toll-Free Svc.','866' => 'Future Toll-Free Svc.','456' => 'Inbound International','011' => 'International Access','555' => 'Not Available','880' => 'Paid 800 Service','881' => 'Paid 888 Service','882' => 'Paid 877 Service','500' => 'Personal Communication Svcs','611' => 'Repair Service','311' => 'Reserved Special Function','200' => 'Service access code','300' => 'Service Access Code','400' => 'Service Access Code','700' => 'Service Varies by LD Carrier','711' => 'Special Function','811' => 'Special Function','800' => 'Toll-Free Calling','877' => 'Toll-Free Calling','888' => 'Toll-Free Calling','900' => 'Value Added Info Svc Code' );

=pod
---+ XXX-YYY-ZZZZ
   * npa - XXX
   * nxx - YYY
Tier 1 means any YYY is available.  Tier 2 means only some YYY are available for a given XXX.
=cut

sub new {
	my $class = shift;	
	my $this;
	
	$this->{base_url} = 'http://carriers.icall.com/api/?';
	
	bless $this, $class;
	
	$this->add_param('key','31117fe4097b26dbeb1a61375b16b648');
	$this->add_param('username','slopyjalopi');

	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	$this->handler(Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new());

	return $this;
}


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

sub key {
	my $this = shift;
	return $this->{key};
}
sub base_url {
	my $this = shift;
	return $this->{base_url};
}
sub param_array {
	my $this = shift;
	return keys %{$this->{'_array'}};
	
}

sub param_value {
	my $this = shift;
	my $name = shift;
	return $this->{'_array'}->{$name};
}

sub add_param {
	my $this = shift;
	my $name = shift;
	my $value = shift;
	return undef unless $name && $value;
	$this->{'_array'}->{$name} = $value;
	return $this->param_array;
}

sub print_url {
	my $this = shift;
	my @url_params;
	foreach my $paramname ($this->param_array){
		push(@url_params,$paramname.'='.$this->param_value($paramname));
	}
	return undef unless length(@url_params) > 0;
	my $url = $this->base_url.join('&',@url_params);
	return $url;
}

sub get_content {
	my $this = shift;
	
	my $url = $this->print_url;
	my $browser = LWP::UserAgent->new;
	my $content = $browser->get($url);
	return undef unless $content;
	
	return $content->{'_content'};
}

=pod
service.getAvailNPA 	List all available NPAs with tier availability

Returns
<rsp stat="ok" version="1.0"><numbers>
<npa tier2="true">207</npa><npa tier1="true" tier2="true">208</npa></numbers></rsp>
=cut
sub service_getAvailNPA {
	my $this = shift;
	$this->add_param('method','service.getAvailNPA');
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	my @array = ( $content =~ /<npa(.*)\/npa>/g );
	foreach my $row (@array) {
		my ($tier1,$tier2,$areacode) = (0,0,0);
		$row =~ /(tier1='([a-z]+)')?\s+tier2='([a-z]+)'\>([0-9]+)/;
		$tier1 = 1 if $2 eq 'true';
		$tier2 = 1 if $3 eq 'true';
		$areacode = $4;
		next unless  $areacode;
		$return_hash->{$areacode}->{'tier1'} = $tier1 if $tier1;
		$return_hash->{$areacode}->{'tier2'} = $tier2 if $tier2;
	}
	return $return_hash;
}

=pod
service.getAvailNPANXX 	List all available NPA and NXXs with tier availability
   * returns XXX-YYY along with tiers
<npanxx npa="201" nxx="228" ratecenter="LEONIA" tier1="true" tier2="true"/><npanxx npa="201" nxx="244" ratecenter="DUMONT" tier1="true" tier2="true"/>
=cut
sub service_getAvailNPANXX {
	my $this = shift;
	$this->add_param('method','service.getAvailNPANXX');
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	foreach my $row (split('/><npanxx',$content)) {
		my ($npa,$nxx,$ratecenter,$tier1,$tier2);
		$row =~ /npa="([0-9]+)"\s+nxx="([0-9]+)"\s+ratecenter="([a-zA-Z0-9]+)"(\s+tier1="([a-z]+)")?\s+tier2="([a-z]+)/;
		$npa = $1;
		$nxx = $2;
		$ratecenter = $3;
		$tier1 = $5;
		$tier2 = $6;
		next unless $npa && $nxx && $ratecenter;
		$return_hash->{$npa}->{$nxx}->{'ratecenter'} = $ratecenter;
		$return_hash->{$npa}->{$nxx}->{'tier1'} = $tier1;
		$return_hash->{$npa}->{$nxx}->{'tier2'} = $tier2;
	}
	return $return_hash;
}


=pod
service.checkNPA 	Check the availability of numbers in a specific NPA
   * npa - the area code the customer wants  
returns:
<number type="tier2">4075121263</number><number type="tier1">407519</number><number type="tier1">407512</number>
=cut
sub service_checkNPA {
	my $this = shift;
	my $npa = shift;
	return undef unless $npa;
	$this->add_param('method','service.checkNPA');
	$this->add_param('npa',$npa);
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	# oh man
	my @array = ( $content =~ /<number(.*)\/number>/g );
	#require Data::Dumper;
	#my $x = Data::Dumper::Dumper(@array);
	#return $x;
	my $return_hash;
	foreach my $row (@array) {
		my ($npanxx,$tiertype);
		$row =~ /type='(tier[12])'>([0-9]+)/;
		$tiertype = $1;
		$npanxx = $2;
		next unless $npanxx && $tiertype;
		# check if it is tier 1, implies $npanxx is only 6 digits, not 10 digits
		if($tiertype eq 'tier1'){
			# $npanxx is only 6 digits
			$return_hash->{$npa}->{$npanxx} = $tiertype;
		}
		elsif(!($return_hash->{$npa}->{$npanxx}))
		{
			# $npanxx is 10 digits and is tier2
			$return_hash->{$npa}->{$npanxx} = $tiertype;
		}

	}
	return $return_hash;
	#$this->handler->fetchMemcached($cache,$key);
	#$this->handler->putMemcached($cache,$key,$value,$expiration_time);
}


=pod
service.checkRateCenter 	Check the availability of numbers in a specific rate center

Returns a lot of phone numbers:
6462899948 6462899949 6462161270 6462183319 6462183334 6468736154 6468736164 9172849013 6464545504 9178292791 9173980402 9173980403 9173980404 9173980405 9173980406 9173980407 9173980408 9173980409 9173980410 9173980411 9173980412 9173980413 9173980414 9173980415 9173980416 9173980417 9173980418 9173980419 9173980420 9173980421 9173980422 9173980423 9173980424 9173980425 9173980426 9173980427
=cut
sub service_checkRateCenter {
	my $this = shift;
	my $ratecenter = shift;
	return undef unless $ratecenter;
	$this->add_param('method','service.checkRateCenter');
	$this->add_param('ratecenter',$ratecenter);
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	my @number_array;
	foreach my $row (split(' ',$content)) {
		my ($fullnumber);
		$row =~ /([0-9]+)/;
		next unless $fullnumber;
		push(@number_array,$fullnumber);
	}
	$return_hash->{$ratecenter} = \@number_array;
	return $return_hash;
}
=pod
service.getRateCenters 	Get a list of the rate centers in a specific state or NPA
<rsp stat="ok" version="1.0"><ratecenters state="AK"><ratecenter city="" state="AK" county=""/><ratecenter city="ADAK" state="AK" county="">ADKUSNVLST</ratecenter><ratecenter city="AKHIOK" state="AK" county="">AKHIOK</ratecenter><ratecenter city="AKIACHAK" state="AK" county="">AKIACHAK</ratecenter><ratecenter city="AKIAK" state="AK" county="">AKIAK</ratecenter><ratecenter city="" state="AK" county="">AKUTAN</ratecenter>

<ratecenter city="ADAK" state="AK" county="">ADKUSNVLST</ratecenter>
=cut
sub service_getRateCenters {
	my $this = shift;
	my $state = shift;
	return undef unless $state;
	$this->add_param('method','service.getRateCenters');
	$this->add_param('state',$state);
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	my @number_array;
	foreach my $row (split('</ratecenter><ratecenter',$content)) {
		my ($city,$state,$county,$ratecenter);
		$row =~ /city="([a-zA-Z]*)"\s*state="([a-zA-Z]*)"\s*county="([a-zA-Z]*)"\s*>([a-zA-Z]*)/;
		$city = $1;
		$state = $2;
		$county = $3;
		$ratecenter = $4;
		next unless $ratecenter && ($city || $state || $county);
		$return_hash->{$state}->{$city.$state.$county}->{'city'} = $city;
		$return_hash->{$state}->{$city.$state.$county}->{'state'} = $city;
		$return_hash->{$state}->{$city.$state.$county}->{'county'} = $county;
		$return_hash->{$state}->{$city.$state.$county}->{'ratecenter'} = $ratecenter;
	}
	return $return_hash;
}

=pod
service.lookupNPANXX 	Return information on a specific NPA/NXX

<npanxx npa="407" nxx="523" state="FL" city="Orlando" county="" ratecenter="ORLANDO"/>
=cut
sub service_lookupNPANXX {
	my $this = shift;
	my ($npa,$nxx) = (shift,shift);
	return undef unless $npa && $nxx;
	$this->add_param('method','service.lookupNPANXX');
	$this->add_param('npa',$npa);
	$this->add_param('nxx',$nxx);
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	foreach my $row (split('/><npanxx',$content)) {
		my ($state,$city,$county,$ratecenter);
		$row =~ /npa="([0-9]*)"\s*nxx="([0-9]*)"\s*state="([a-zA-Z]*)"\s*city="([a-zA-Z]*)"\s*county="([a-zA-Z]*)"\s*ratecenter="([a-zA-Z]*)"/;
		$npa = $1;
		$nxx = $2;
		$state = $3;
		$city = $4;
		$county = $5;
		$ratecenter = $6;
		next unless $npa && $nxx && ($ratecenter);
		$return_hash->{$npa}->{$nxx}->{'city'} = $city;
		$return_hash->{$npa}->{$nxx}->{'state'} = $city;
		$return_hash->{$npa}->{$nxx}->{'county'} = $county;
		$return_hash->{$npa}->{$nxx}->{'ratecenter'} = $ratecenter;
	}
	return $return_hash;
}
=pod
service.reserveDID 	Reserve the specified DID for 60 minutes at no charge
key 	31117fe4097b26dbeb1a61375b16b648 	Your API key
method 	service.reserveDID 	The method name
number 	2125551212 	The requested number to reserve
testing 	true 	If this parameter is set, it will always return success regardless of the number sent.

Returns:
<did status="reserved" expiration="2012-05-30 09:55:22">2053324456</did>
=cut
sub service_reserveDID {
	my $this = shift;
	my ($number,$testing) = (shift,shift);
	return undef unless $number;
	$this->add_param('method','service.reserveDID');
	$this->add_param('number',$number);
	$this->add_param('testing',$testing) if $testing eq 'true';
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	foreach my $row (split('/><npanxx',$content)) {
		my ($status,$expiration,$number);
		$row =~ /status="([a-z])"\s*expiration="([0-9-\s:]*)">([0-9]*)"/;
		$status = $1;
		$expiration = $2;
		$number = $3;
		next unless $status;
		$return_hash->{$number}->{'status'} = $status;
		$return_hash->{$number}->{'exipration'} = $expiration;		
	}
	return $return_hash;
}

=pod
service.orderDID 	Order a specific DID
key 	31117fe4097b26dbeb1a61375b16b648 	Your API key
method 	service.orderDID 	The method name
number 	2125551212 	The requested number to order. This may be a 6 or 10-digit number.
tier 	1 	The number tier - if left blank, it will "1" for 10-digit numbers and "2" for 6-digit numbers.
routing 	cust_username 	The sub-account to route this DID to - if left blank, it will be your account default
testing 	true 	If this parameter is set, it will always return success regardless of the number sent.
service_order(number,testing,tier,routing)->order number
=cut

sub service_orderDID {
	my $this = shift;
	my ($number,$testing) = (shift,shift);
	my ($tier,$routing) = (shift,shift);
	return undef unless $number;
	$this->add_param('method','service.orderDID');
	$this->add_param('number',$number);
	$this->add_param('testing',$testing) if $testing eq 'true';
	$this->add_param('tier',$tier) if $tier;
	$this->add_param('routing',$routing);
	my $content = $this->get_content();
	# we should use an xml parser, but that is too complicated
	# let's use simple regex
	my $return_hash;
	foreach my $row (split('/><npanxx',$content)) {
		my ($status,$expiration,$number);
		$row =~ /status="([a-z])"\s*expiration="([0-9-\s:]*)">([0-9]*)"/;
		$status = $1;
		$expiration = $2;
		$number = $3;
		next unless $status;
		$return_hash->{$number}->{'status'} = $status;
		$return_hash->{$number}->{'exipration'} = $expiration;		
	}
	return $return_hash;
}


=pod
service.removeDID 	Remove a specific DID
=cut
sub service_removeDID {
	my $this = shift;
	my ($number,$testing) = (shift,shift);
	my ($tier,$routing) = (shift,shift);
	return undef unless $number;
	$this->add_param('method','service.removeDID');
	$this->add_param('number',$number);
	$this->add_param('testing',$testing) if $testing eq 'true';
	my $content = $this->get_content();
	return $content;
	
}
=pod
service.setRouting 	Change the sub-account a DID is routed to 
key 	31117fe4097b26dbeb1a61375b16b648 	Your API key
method 	service.setRouting 	The method name
number 	2125551212 	The number to update
routing 	cust_username_123_123_123_123 	The sub-account to route to. This can be a registration or IP-based account. For IPs, 
			the sub-account IP is appended to "cust_username_" with the "."s replaced with "_"s. For example, 
			an IP of 123.123.123.123 would be "cust_username_123_123_123_123".
=cut
sub service_setRouting {
	my $this = shift;
	my ($number,$routing) = (shift,shift);
	return undef unless $number && $routing;
	$this->add_param('method','service.setRouting');
	$this->add_param('number',$number);
	$this->add_param('routing',$routing);
	my $content = $this->get_content();
	return $content;
}
=pod
term.getRate
key 	31117fe4097b26dbeb1a61375b16b648 	Your API key
method 	term.getRate 	The method name
number 	2125551212 	The requested number to get a rate for (can be either a 6-digit NPA/NXX combo or a full 9-digit number with area code). Do not include dashes.
=cut
sub term_getRate {
	my $this = shift;
	my ($number) = (shift);
	return undef unless $number;
	$this->add_param('method','service.setRouting');
	$this->add_param('number',$number);
	my $content = $this->get_content();
	return $content;
}

=pod
Purchase a number and add it to e-flamingo Inventory
=cut
sub purchase_number {
	my $this = shift;
	my $number = shift;
	my ($testing,$tier) = ('','');
	my $routing = 'cust_slopyjalopi_vps-linode02';
	# reserve the number first
	$this->service_reserveDID($number,$testing,$tier,$routing);
	
	# add the number to wiki database
	
	# 
}
=pod
---+ %DIDPROVIDER1{""}%
It was not named iCallInfo because it is best for customers to not know that iCall is a supplier of E-Flamingo (competitive reasons).
   1. Pick an NPA
   2. Pick an NXX
   3. Get your number (can't pick the last 4 numbers)
=cut

sub display{
	my ($inWeb,$inTopic, $args) = @_;
	my $session = $Foswiki::Plugins::SESSION;

	# get the Order web,topic pair
	require Foswiki::Func;
	my $did_topic_WT = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	$did_topic_WT = $session->{webName}.'.'.$session->{topicName} unless $did_topic_WT;
	
	my $main_arg = Foswiki::Func::extractNameValuePair( $args );
	my $npa_arg = Foswiki::Func::extractNameValuePair( $args, 'ZZZ' );
=pod	
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
=cut


	return pick_areacode() if $main_arg eq 'areacode';
	return pick_phonenumber($npa_arg) if $main_arg eq 'number';

}

=pod
---+ "areacode"
let's the user select from all of the areacodes available
outputs html
=cut
sub pick_areacode {
	my $iCall = Foswiki::Plugins::AccountsPlugin::iCall::->new();
	# fetch info from iCall
	my $return_hash = $iCall->service_getAvailNPA();

	my $html = '<select id="ZZZ" name="ZZZ">';
	foreach my $areacode (sort (keys(%{$return_hash}))) {
		$html .= '<option value="'.$areacode.'">'.$areacode.' : '.$code_list{$areacode}.'</option>';
	}
	$html .= '</select>';
	return $html;
}
=pod
---+ "phonenumber"
let's the user select a phone number from all of the areacodes available
outputs html
=cut
sub pick_phonenumber {
	my $npa = shift;
	return undef unless $npa =~ m/([0-9]{3})/;
	# check that $npa is a legitamate areacode
	return undef unless $code_list{$npa};;
	my $iCall = Foswiki::Plugins::AccountsPlugin::iCall::->new();
	# fetch info from iCall
	my $return_hash = $iCall->service_checkNPA($npa);
	# $return_hash->{$npa}->{$npanxx}
	my $html = '<select id="ZZZXXX" name="ZZZXXX">';
	foreach my $npanxx (sort (keys(%{$return_hash->{$npa}}))) {
		# make the phone numbers look like: ZZZ-XXX-YYYY
		$npanxx =~ /([0-9]{3})([0-9]{3})([0-9]{4})?/;
		my ($zzz,$xxx,$yyyy) = ($1,$2,$3);
		$yyyy = 'YYYY' unless $yyyy;
		$html .= '<option value="'.$npanxx.'">'."$zzz-$xxx-$yyyy".'</option>';
	}
	$html .= '</select>';
	return $html;
	require Data::Dumper;
	my $x = Data::Dumper::Dumper($return_hash);
	return $x;
}


1;
__END__
