package CGI::Persist::File;

BEGIN {
  $CGI::Persist::File::VERSION = '2.1';
}

## The file-based frontend to CGI::Persist.
##
## See CGI::Persist for more gory details.
##

##############################################################################
#
# THE MODULE INITIALIZATIONS
##############################################################################

use strict;
no strict 'refs';

use base 'CGI::Persist';
use IO::File;

# modules accessors
use Class::AccessorMaker::Private {
  root => '/tmp',
  prefix => '',
  umask => '002',
	
  FileHandle => undef,
  FileName => undef,
  MODE => "." }, "no_new";

# my globals.
use vars qw($VERSION);
$VERSION = '1.0';

##############################################################################
#
# CONSTRUCTOR
##############################################################################

sub new {
  ## Constructor.
  ##
  ## I was going to skip it and have the base-class deal with it, but
  ## the CGI::Persistent interface made this impossible (allas!)
  ##

  my $class = ref($_[0]) || $_[0]; shift;

  # make sure the user can do like CGI::Persistent.
  @_ = (root => $_[0]) if ( $#_ == 0 );

  push @_, (no_init => 1);      # CGI::Persist must not init yet!

  # have SUPER handle the rest.
  my $base = $class->SUPER::new(@_);
  my $self = bless($base,$class);

  # init.
  $self->MODE("");
  $self->init();

  return $self;
}

##############################################################################
#
# DB I/O (a file in this case - but the base class doesn't know ;^)
##############################################################################

sub openDB {
  ## NAME
  ##   openDB
  ##
  ## DESCRIPTION
  ##  creates filename out of ->root, ->prefix and ->ID. Creates a new
  ##  IO::File object in ->FileHandle.
  ##
  ## SYNOPSIS
  ##
  ##   $self->openDB();
  ##

 die ("Don't you ever touch my balls without asking!\n")
    if !( caller =~ /Persist/ );

  my ($self) = @_;

  # formulate a filename.
  my $FN = $self->root . "/";
  die ( "You must specify a storage root" ) if $FN eq "/";
  $FN .= $self->prefix . "-" if $self->prefix;
  $FN .= $self->ID;

  # set propper umask
  umask $self->umask;

  # clean-up not so pretty things.
  $FN =~ s/\/\//\//g;	# // -> /

  $FN = "" if ( !$self->ID );
  $FN = $self->untaint($FN);
  $self->FileName($FN);

  my $IO = IO::File->new();
  $self->FileHandle($IO);

  return 1;
}

sub closeDB {
  ## NAME
  ##   closeDB
  ##
  ## DESCRIPTION
  ##   Closes the ->FileHandle (if still open...) and undefines the ->FileName
  ##
  ## SYNOPSIS
  ##
  ##  $self->closeDB
  ##

  my ( $self ) = @_;

  $self->FileHandle->close;
  $self->FileHandle(undef);
  $self->FileName(undef);
  $self->MODE(undef);

}

sub get {
  ## NAME
  ##  get
  ##
  ## DESCRIPTION
  ##   Restores the frozen data from the DB, that belongs to an ID.
  ##
  ## SYNOPSIS
  ##
  ##   $self->get();          # get data for current ID.
  ##
  ##   $self->get("kiH3Fa");  # get data for kiH3Fa
  ##

  my ($self, $ID) = @_;
  $ID ||= $self->ID;

  # 'reset' DB
  $self->closeDB if ( $self->MODE eq "w" );
  $self->MODE("r");
  $self->openDB;

  # INPUT-RECORD-SEPERATOR to nil.
  local $/="";

  $self->FileHandle->open($self->FileName, $self->MODE)
    || $self->ID("");           # open else reset 'ID'

  if ( $self->ID ) {
    $self->log("get " . $self->ID);
  } else {
    $self->log("get " . $self->ID . " failed!");
  }

  my $FH = $self->FileHandle;

  my $frozen = <$FH>;
  my $bytes = length($frozen);
  $self->deserialize($frozen);
}

sub store {
  ## NAME
  ##  store
  ##
  ## DESCRIPTION
  ##   Stores the data.
  ##
  ##   Calls upon clean_up to clean up. This makes things a bit more
  ##   slow, but if all is well, there shouldn't be a store called by
  ##   the user (they CAN do it however)
  ##
  ## SYNOPSIS
  ##   $self->store(1);      # supplying 1 means: newSession.
  ##

  my ($self, $create) = @_;

  $self->closeDB if ( $self->MODE eq "r" );

  $self->MODE("w");
  $self->openDB;

  $self->log("store " . $self->ID);

  $self->filterSessionData() unless $create;
  my $frozen = $self->serialize();

  if ( $frozen ) {
    $self->FileHandle->open($self->FileName, $self->MODE)
      || die("Can't open " . $self->FileName . "\n");

    $self->FileHandle->print($frozen);
    my $bytes = length($frozen);
  }

  $self->cleanUp;
}

##############################################################################
#
# CLINSING MATERIALS.
##############################################################################

sub untaint {
  ## NAME
  ##   untaint
  ##
  ## DESCRIPTION
  ##   Great clinsin material in a File based script...
  ##
  ## SYNOPSIS
  ##   $saveFileName = $self->untaint($fileName);

  my ( $self, $tainted ) = @_;

  # first check for bad sequences in filename(s).
  die "Chosen CGI::Persist::File->root(" . $self->root() . ") is not safe\n"
    if $tainted =~ m/\.\.\//;

  ($tainted) = $tainted =~ m/^([\w\d\_\-\.\/]+)/;
  return $tainted;
}

sub findOldSessions {
  ## NAME
  ##  find_old
  ##
  ## DESCRIPTION
  ##   Finds a list of old ID's in the temp-root.
  ##   stat is used for this, and if you expect a lot of traffic it is
  ##   not wise to have this called (Which is done if you have
  ##   AUTOCLEAN set to 1)
  ##
  ## SYNOPSIS
  ##
  ##  $self->find_old
  ##

  my ( $self, $old ) = @_;
  $old ||= (time() - $self->sessionTime);

  $self->log("finding old files");

  my @list = ();
  my $prefix = $self->prefix;

  my $DIR;
  opendir($DIR, $self->root);

  while(my $read = readdir($DIR)) {
    next if ( $read =~ /^\.+$/ || !$read );

    my (@stat) = stat $self->root . "/$read";
    if ( $prefix ) {
      push @list, $read if ( $read =~ /^$prefix/ && $stat[9] < $old );
    } elsif ( length($read) < 10 && length($read) >= 6 ) {
      push @list, $read if ( $stat[9] < $old );
    }
  }
  closedir($DIR);

  return @list;
}

sub clean {
  ## NAME
  ##   clean
  ##
  ## DESCRIPTION
  ##   Cleans a list of ID's
  ##
  ## SYNOPSIS
  ##
  ##   $self->clean(@list);
  ##

  my ( $self, @list ) = @_;

  return 1 if !@list;

  $self->log("Starting clean-up");

  for my $element (0..$#list) {
    my ($file) = $list[$element] =~ m/^([\w\d\_\.\-]+)/;
    $list[$element] = $self->root . "/$file";
  }

  my $id_list = join(", ", @list);
  my $cnt = unlink @list;

  my $log = "Clean_up: " . $id_list . " ($cnt succesfull)";
  $self->log($log);
  return ($#list - $cnt);
}


1;

__END__

=pod

=head1 DESCRIPTION

Persistency module using CGI::Persist.

CGI::Persist::File is the file-based front end to CGI::Persist

CGI::Persist is capable of preventing 'session-stealing'
because it checks REMOTE_ADDR and HTTP_USER_AGENT of the guy (or gal)
on the other end of the line.

=head1 SYNOPSIS

  use strict; #|| die!
  my $p = CGI::Persist::File->new(root => "Foo",
                                  prefix => "myscript",

                                  sessionTime => 900,
				 );

    # add a parameter to the data.
    $p->param(-name => "Veggie", -value = "TRUE");

    # read a parameter from the data.
    $id = $p->param('id') || $p->ID;

    # store something completely else
    $p->data(MyName => "Hartog C. de Mik",
	     key => "0294202049522095");

=head1 METHODS

=over 4

=item * root

Specify the /path/to for your files. Defaults to /tmp. 
If you use "../" in your root() CGI::Persist::File causes a die.

=item * prefix

Specify the prefix to use for your files. If you have something like

  $cgi->root("/www/sessions");
  $cgi->prefix("MyScript");

filenames will look like:

  /www/sessions/MyScript-Fw8WQJ

When ->prefix() is empty filenames would look like:

  /www/sessions/Fw8WQJ

=back

=head1 SEE ALSO

CGI(3), CGI::Persist

=head1 AUTHOR

Hartog C. de Mik, hartog@2organize.com

=cut
