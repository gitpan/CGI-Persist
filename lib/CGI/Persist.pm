package CGI::Persist;

BEGIN {
  $CGI::Persist::VERSION = 2.2;
  $CGI::Persist::TEST    = 0;
}

# init.
use strict;
use base qw(CGI);
use Fcntl qw(:flock);
use Carp;

# modules for storage.
use Storable qw(nfreeze thaw);
use MIME::Base64;
use Date::Format;
use POSIX qw(tmpnam);

# constants
use constant DEF_EXP_TIME => 900; 
our %obj_;

# class definition
use Class::AccessorMaker::Private {
  # General object attribute
  ID => "",
  sessionTime => DEF_EXP_TIME,
  no_init => 0,
  logFile      => "",
  errorLogFile => "",

  # object hooks
  writeOnce => [],
  filter    => [],
  mask      => [],

  run => sub { return undef },

  # Persistent object attributes
  firstRun => 0,
  newFromIdle => 0,
  locked => 0,
  timestamp => 0,
  stored => 0,
}, "no_new";

sub new {
  my $class = ref($_[0]) || $_[0]; shift;

  if ( $#_ > 0 && "$#_" !~ /[13579]$/ ) {
    die("Not a hash-like set of parameters for Persist::new()\n");
  }

  # setup the object;
  my $qstring = $ENV{QUERY_STRING};
  $qstring = undef unless $CGI::Persist::TEST == 1;

  my $obj = CGI->new($qstring);
  my $self = bless($obj,$class);

  while (my($key,$value)=splice(@_,0,2)) {
    $self->$key($value) if UNIVERSAL::can($self, $key);
  }

  # Initialize the object.
  $self->init() unless $self->no_init;

  return $self;
}

sub init {
  my ( $self ) = @_;
  
  $obj_{$self}->{data} = {};

  # get session
  my $id = ( $self->param("ID") or 
	     $self->param("id") or 
	     $self->param(".id") or 
	     $self->param(".ID") );

  my $givenID;
  $givenID = 1 if ( $id );

  $self->ID($id);

  # get prev. session or begin a new one.
  $self->log( join(", ", map { "$_ => " . $self->param($_) } $self->param) );
  if ( validID($self->ID) ) {
    $self->get();
  } else {
    $self->errorLog("session-id: " . $self->ID . " : invalid!") if $self->ID;
    $self->newSession;
  }

  # check mischief.
  my ($dataIP) = ($self->data("REMOTE_ADDR")||"") =~ /((\d+\.){3})\d+/;
  my ($envIP) = ($ENV{"REMOTE_ADDR"}||"") =~ /((\d+\.){3})\d+/;

  my $missingData = (!$self->data("HTTP_USER_AGENT") 
		     or !$self->data("REMOTE_ADDR"));
  my $wrongData = ((
		    ($self->data("HTTP_USER_AGENT")||"") ne 
		    ($ENV{HTTP_USER_AGENT}||""))
		   or (($dataIP||"") ne ($envIP||"")));

  if ( $missingData or $wrongData ) {
    $self->errorLog($self->ID . " session was lost") if $missingData;
    $self->errorLog($self->ID . " session stealing attempt ($dataIP $envIP)") if $wrongData and !$missingData;
    $self->newFromIdle(1) if $givenID;
    $self->newSession;
  }

  $self->param(-name => "ID", -value => $self->ID);

  # run the run.
  &{$self->run()} if defined $self->run;

  return $self;
}

#############################################################################
#
# IO interface
#############################################################################

sub openDB { return undef }
sub closeDB { return undef }
sub get { return undef }
sub store { return undef }

#############################################################################
#
# Data / session interface
#############################################################################

sub newSession {
  my ($self) = @_;

  my ($newID) = tmpnam =~ m/(.{6})$/;
  $self->ID($newID);

  $obj_{$self} = {};		# clean it all;

  $self->data("REMOTE_ADDR" => $ENV{REMOTE_ADDR},
	      "HTTP_USER_AGENT" => $ENV{HTTP_USER_AGENT});
  $self->timestamp(time);
  $self->store(1);
  $self->firstRun(1);

  return;
}

sub serialize {
  my ($self, $unfrozen) = @_;

  # gather unfrozen data if non given.
  unless ($unfrozen) {
    $unfrozen->{data} = $obj_{$self}->{data};
    $unfrozen->{data}->{_locked} = $self->locked;
    $unfrozen->{writeOnce} = $self->writeOnce;
    $unfrozen->{timestamp} = $self->timestamp;

    foreach my $par ( $self->param ) {
      $unfrozen->{param}->{$par} = [ $self->param($par) ];
    }
  }

  my $data = nfreeze($unfrozen);
  $data = encode_base64($data);
  return $data;
}

sub deserialize {
  my ($self, $frozen) = @_;
  return undef if !$frozen;

  # find out envirnoment parameters
  foreach my $p ( $self->param()){
    my @val = $self->param($p);
    $obj_{$self}->{currentparam}->{$p} = [ @val ];
  }

  my $data = decode_base64($frozen);
  $data = thaw($data);

  # retrieve writeOnce
  $self->writeOnce($data->{writeOnce});
  delete $data->{writeOnce};

  # re-set parameters
  while(my ($name,$value) = each %{$data->{param}}) {
    if ( defined $self->param($name) ) {
      if ( elementOf($self->writeOnce, $name) ) {
	# this parameter is writeonce - overwrite with data.
	$self->param(-name => $name, -value => $value);
      }
    } else {
      # reset this parameter.
      $self->param(-name => $name, -value => $value);
    }
  }
  delete $data->{param};

  # re-set data
  $self->locked($data->{data}->{_locked});
  delete $data->{data}->{_locked};

  while(my ($name,$value) = each %{$data->{data}}) {
    $self->data($name => $value);
  }
  delete $data->{data};

  # re-set sessions original timestamp;
  $self->timestamp($data->{timestamp});
  delete $data->{timestamp};

  $self->errorLog("Found un-understood keys: \"" .
		  join(", ", keys %$data) .
		  "\" in \$data during deserialize") if ( keys %$data );

  return 1;
}

sub data {
  my ( $self ) = shift;
  my ($tag, $val);

  if ( $#_ > 0 && $#_ =~ /[13579]$/) {
    # set values
    while(($tag, $val) = splice(@_,0,2)) {
      $obj_{$self}->{data}->{$tag} = $val;
    }

  } else {
    # caller wants the value of one data thing.
    $tag = shift;
    if ( $tag ) {
      $val = $obj_{$self}->{data}->{$tag};
      return $val;
    } else {
      return keys %{$obj_{$self}->{data}};
    }
  }
}

# prevent API collisions.
sub currentparam {
  return currentParam(@_);
}

sub got_submit {
  return gotSubmit(@_);
}

sub currentParam {
  my ($self, $param) = splice(@_,0,2);

  if ( $#_ > 0 ) {
    croak("currentParam doesn't support 'set'")
  } elsif ( ! defined($param) ) {
    return(keys %{$obj_{$self}->{currentparam}});
  }

  my $array = $obj_{$self}->{currentparam}->{$param};
  if ( $array ) {
    return wantarray ? @{$array} : $array->[0]
  }

  return undef;
}

sub gotSubmit{
  my ($self,$button) = @_;

  return($self->currentParam($button) || 
         $self->currentParam($button . ".x"));
}

sub lockSession {
  my $self = shift;

  my $timestamp = time();
  $timestamp =~ tr/[0-8]/9/;

  $self->store(undef,$timestamp);
}

#############################################################################
#
# Clean and filter
#############################################################################

sub cleanUp {
  my ($self) = @_;
  my @deleteThese = $self->findOldSessions;
  $self->clean(@deleteThese);
}

sub findOldSessions { return undef }
sub clean { return undef }

sub filterSessionData {
  my ( $self ) = @_;
  return 0 if ( !@{$self->mask()} && !@{$self->filter()} );

  my @objectMask = grep { $_ } @{$self->mask};
  my @objectFilter = grep { $_ } @{$self->filter};

  my (@mask, @filter, @remove);
  my $logString;
  my @list = ($self->param);

  { # remove all parameters not masked by $self->mask;
    my $regex = join("|", @objectMask);
    if ( $regex && $regex !~ /^\|+$/ ) {
      $regex =~ s/\*/\.\*/;
      push @mask, (grep { !/^$regex$/ } @list);
    }
    $logString = "removed due to mask : " . join(", ", @mask) if @mask;
  }

  { # remove all parameters filtered by $self->filter
    my $regex = join("|", @objectFilter);
    if ( $regex && $regex !~ /^\|+$/ ) {
      $regex =~ s/\*/\.\*/g;
      push @filter, (grep { /^$regex$/ } @list);
    }
    $logString .= " and " if $logString;
    $logString .= "removed due to filter : " . join(", ", @filter) if @filter;
  }
  push @remove, (@mask, @filter);

  # remove ID from remove...
  @remove = grep { ($_ ne "id"   or   $_ ne "ID") } @remove;
  $self->log($logString) if (@filter or @mask);

  # remove from parameter list.
  $self->delete($_) foreach @remove;

  return;
}


#############################################################################
#
# Logging mechanism
#############################################################################

sub log {
  my ($self, $msg, $file) = @_;

  # beautify vars.
  $file ||=$self->logFile;
  return undef if !$file;
  $msg .= "\n" if $msg !~ /\n$/m;

  my $ID = $self->ID || "no-ID";

  if ( open(LOG, ">>$file") ){
    flock(LOG, LOCK_EX);
    seek(LOG, 0, 2);
    print LOG join("\t", time, $ID, $msg);
    flock(LOG, LOCK_UN);
    close(LOG);
  } else {
    warn("CGI::Persist::log(), $file: $!");
  }

  return 1;
}

sub errorLog {
  my ($self, $msg) = @_;
  if ( $self->errorLogFile ) {
    return $self->log($msg, $self->errorLogFile);
  } else {
    warn($msg . " at " . join(" ", caller()) . "\n");
  }
}

#############################################################################
#
# Class goodies
#############################################################################

sub paramFetchHash {
  return param_fetchhash(@_);
}

sub param_fetchhash {
  my ( $self ) = @_;
  my %hash;
  $hash{$_} = $self->param($_) foreach ( $self->param() );
  return %hash;
}

sub href {
  ## Creates a href with an ID in the link.
  my ($self, $link, $text) = @_;
  my $sig;

 if ( $link && $link =~ /\?/ ) {
    $sig = "&";
  } else {
    $sig = "?";
  }
  return "<a href=\"" .  $link . $sig . "ID=" . $self->ID() . "\">$text</a>";
}

sub stateUrl {
  return state_url(@_);
}

sub state_url {
  ## For $self->Persistent users...
  my ( $self ) = @_; 
  return $self->url ."?ID=".$self->ID;
}

sub stateField {
  return state_field(@_);
}

sub state_field {
  ## For $self->Persistent users...
  my ( $self ) = @_;
  return "<input type=hidden name=\"ID\" value=\"" . $self->ID . "\">";
}

sub DESTROY {
  my ($self) = @_;
  
  $self->store;
  $self->closeDB;
  undef $self;
}

#############################################################################
#
# Toolbox
#############################################################################

sub elementOf {
  my ($array, $item) = @_;

  my @indices;
  for(0..$#{$array}) {
    if ( $item && $item eq $array->[$_]) {
      push @indices, $_;
    }
  }
  return @indices;
}

sub validID {
  my $id = shift;
  return undef if !$id;
  return ($id =~ /[\w\d]{6,10}/) ? 1 : 0;
}

1;

__END__

=pod

=head1 NAME

CGI::Persist -- Web persistency made usable.

=head1 SYNOPSIS

  my $cgi = CGI::Persist->new(sessionTime => 60);

=head1 DESCRIPTION

The base class for CGI::Persist::DBI and CGI::Persist::File, is NOT capable of storing anything for itself (not even using cookies - since they are evil)

This all gives you full access to the CGI interface.

=head1 FUNCTIONS

=over 3

=item new 

  ( sessionTime => 900, 
    logFile => " ", 
    errorLogFile => " ", 
    writeOnce => [ ], 
    filter => [ ], 
    mask => [ ], 
    run => sub { return undef } );

Creates a new instance of the CGI::Persist object. Running this once should be enough.

=item newSession

Creates a new session. It will not overwrite the current session object in the DB.

=item newFromIdle

Is set to 1 if the previous session has dissapeared and a new session
had to be created.

=item firstRun

Is set to 1 if this is the first hit on a session.

=item data (key)

=item data (key => value)

If the only argument is a key, the matching piece of data is found to
that, and returned. If a value is also submitted this will be stored.

In void context an anonymous hash is returned with all key => value
pairs inside.

=item currentParam

Holds the 'current' parameters (eg: the parameters that where found
before the session was restored.);

=item gotSubmit

Feature for checking (image)buttons have been pressed

=item cleanUp

Will round up all the sessions older then sessionTime and ask to delete them.

=item log

writes to the logFile

=item errorLog

writes to the errorLogFile

=item paramFetchHash

returns an anonymous hash of all parameters in memory.

=item href

returns a CGI::href, but with an ID nicely tucked in there.

=item stateUrl

return the current URL + '?ID=$ID'

=item stateField

returns a hidden-field tag for your form holding ID and its value

=back

=head1 WRITING YOUR OWN CHILD

isnt to hard. Just make sure it has the following routines:

  openDB
  closeDB
  store
  get
  findOldSessions
  clean($id)

And make sure that these routines do what their names promisse.

=head1 KNOWN BUGS

None so far.

=head1 CHANGELOG

20051209 : Discoverd that value arrays are not stored correctly, Fixed.
20051219 : Prevented lots of warnings due to more defensive if/unless constructions
         : Added test for DBI

=head1 THANKS TO

Robert Bakker <robert@2organize.com>
Arno F. Roelofs <arnofr@2organize.com>

=head1 AUTHOR

Hartog C. de Mik <hartog@2organize.com>
