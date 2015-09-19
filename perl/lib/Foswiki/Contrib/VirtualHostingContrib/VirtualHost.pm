package Foswiki::Contrib::VirtualHostingContrib::VirtualHost;

use File::Basename;
use Foswiki::Contrib::DBIStoreContrib::Handler ();
use Cwd;
our $CURRENT = undef;

BEGIN {
  if (!$Foswiki::cfg{VirtualHostingContrib}{VirtualHostsDir}) {
    my $path = Cwd::abs_path($Foswiki::cfg{DataDir} . '/../virtualhosts');
    $path =~ /(.*)$/; $path = $1; # untaint, we trust Foswiki configuration

    $Foswiki::cfg{VirtualHostingContrib}{VirtualHostsDir} = $path;
  }
}

sub find {
  my ($class, $hostname, $port) = @_;
  #$hostname = 'e-flamingo.net' unless $hostname;
  #$hostname = _validate_hostname($hostname);
  
  # this is the ip address (or local dns name) of the wiki
  my $urlhost = $Foswiki::cfg{DefaultUrlHostSimple};
  
  # for localized hosts, set the name of the site account
  if($urlhost){
    $hostname = $urlhost;    
  }
  

  # check whether the given virtual host directory exists or not
  if (!$class->exists($hostname)) {
    return undef;
  }

  my $DataDir         = $Foswiki::cfg{DataDir};
  my $WorkingDir      = $Foswiki::cfg{WorkingDir};
  my $PubDir          = $Foswiki::cfg{PubDir};
  my $self            = {
    hostname => $hostname,
    directory => "/var/www/wiki/core",
    config => {
      DataDir               => $DataDir,
      PubDir                => $PubDir,
      WorkingDir            => $WorkingDir,
      DefaultUrlHost        => "http://$urlhost" . ($port && ($port ne '80') && ($port ne '443') ? (':' . $port) : ''),
      # values defined in terms of DataDir
      Htpasswd => {
        FileName            => "$DataDir/.htpasswd",
      },
      ConfigurationLogName  => "$DataDir/configurationlog.txt",
      DebugFileName         => "$DataDir/debug%DATE%.txt",
      WarningFileName       => "$DataDir/warn%DATE%.txt",
      LogFileName           => "$DataDir/log%DATE%.txt",
      RCS => {
        WorkAreaDir         => "$WorkingDir/work_areas",
      },
      TempfileDir           => "$WorkingDir/tmp",
    }
  };
  # check to see what the default URL Host is 1 more time
  if($port eq '80'){
  	# leave as is
  }
  elsif($port eq '443'){
  	# change http to https
  	$self->{config}->{DefaultUrlHost} = "https://$urlhost";
  	$self->{config}->{PermittedRedirectHostUrls} = "http://$urlhost";
  }
  


  bless $self, $class;

  $self->_load_config();

  return $self;
}

sub hostname {
  my $self = shift;
  return $self->{hostname};
}

sub exists {
  my ($class, $hostname) = @_;
  return 1;
}

sub run {
  my ($self, $code) = @_;

  local $Foswiki::Contrib::VirtualHostingContrib::VirtualHost::CURRENT = $self->hostname;

  local @Foswiki::cfg{keys %{$self->{config}}} = map { _merge_config($Foswiki::cfg{$_}, $self->{config}->{$_}) } (keys %{$self->{config}});

  &$code();
}

sub _merge_config {
  my ($global, $local)= @_;
  if (ref($global) eq 'HASH' && ref($local) eq 'HASH') {
    # merge hashes
    my %newhash = %{$global};
    for my $key (keys(%{$local})) {
      $newhash{$key} = _merge_config($global->{$key}, $local->{$key});
    }
    \%newhash;
  } else {
    $local;
  }
}

# StaticMethod
sub run_on_each {
  my ($class, $code) = @_;
  my @hostnames = map { basename $_} glob($Foswiki::cfg{VirtualHostingContrib}{VirtualHostsDir} . '/*');
  @hostnames = grep { $class->exists($_) && $_ ne '_template' } @hostnames;
  for my $hostname (@hostnames) {
    my $virtual_host = $class->find($hostname);
    $virtual_host->run($code);
  }
}

sub _config {
  my ($self, $key) = @_;
  return $self->{config}->{$key} || $Foswiki::cfg{$key};
}

sub _validate_hostname {
  my $hostname = shift;
  return undef unless $hostname;
  if ($hostname =~ /^[\w-]+(\.[\w-]+)*$/) {
    return $&;
  } else {
    return undef;
  }
}

sub _template_path {
  my $self = shift;
  my $virthostref = shift;

  my $sysname = $virthostref->{SystemWebName};
  die "No System Name: $sysname\n" unless $sysname;
  my $TemplateDir = $Foswiki::cfg{TemplateDir};
  die "No Template Directory\n" unless $TemplateDir;
  my $TemplatePath = $TemplateDir.'/$web/$name.$skin.tmpl, '.$TemplateDir.'/$name.$skin.tmpl, 
  		$web.$skinSkin$nameTemplate, '.$sysname.'.$skinSkin$nameTemplate, 
  		'.$TemplateDir.'/$web/$name.tmpl, '.$TemplateDir.'/$name.tmpl, $web.$nameTemplate, '.$sysname.'.$nameTemplate';
  $self->{config}->{TemplatePath} = $TemplatePath;
}

sub _load_config {
	my $self = shift;
	my $hostname = $self->{hostname};
 	# load the site_handler
 	$self->_setupDBIHandler($hostname);
	my %VirtualHost = %{$self->{config}->{DBIStoreContribSiteHandler}->getVirtualHostConfig()};
	$VirtualHost{SiteName} = $hostname unless $Foswiki::cfg{SiteName};
	$self->_template_path(\%VirtualHost);
  	# Read the configuration information here!
	for my $key (keys(%VirtualHost)) {
		$self->{config}->{$key} = $VirtualHost{$key};
	}
}

sub _setupDBIHandler {
	my $self = shift;
	my $hostname = shift;
	my $site_name = $hostname unless $Foswiki::cfg{SiteName};
	$site_name = $Foswiki::cfg{SiteName} if $Foswiki::cfg{SiteName};
	
	return undef unless $site_name;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->cginew($site_name);

	
	$self->{config}->{DBIStoreContribSiteHandler} = $handler;
	
}

1;
