package CGI::Persist::DBI;

BEGIN {
  $CGI::Persist::DBI::VERSION = '2.1';
}

# init
use strict;
use base qw(CGI::Persist);

use Class::AccessorMaker {
  dbh => {},

  driver => "",
  db => "",
  host => "",
  user => "",
  pass => "",
}, "no_new";

# IO
sub openDB {
  my($self) = @_;

  return if $self->dbh || $self->{".dbOpen"};

  unless ( exists $INC{"DBI.pm"} ) { eval "use DBI;"; }

  my $dsn = "DBI:" . $self->driver . ":database=" . $self->db . ";";
  $dsn .= "host=" . $self->host . ";" if $self->host;
  $dsn .= "user=" . $self->user . ";" if $self->user;
  $dsn .= "pass=" . $self->pass . ";" if $self->pass;
  $self->dbh(DBI->connect($dsn));

  $self->{".dbOpen"} = 1;
}

sub get {
  my($self) = @_;
  $self->openDB;

  my @row = $self->dbh->selectrow_array("SELECT session_info FROM sessions ".
					"WHERE ID=?", {}, $self->ID);
  $self->deserialize($row[0]);

  $self->{".dbOpen"} = 1 if ( $self->dbh );

  return 1;
}

sub store {
  my ($self, $create, $timestamp) = @_;
  $self->openDB;
  $timestamp ||=time();

  $self->filterSessionData unless $create;

  if ($create) {
    # insert
    $self->dbh->do("INSERT INTO sessions (ID, session_info, timestamp) ".
		   "VALUES (?,?,?)", {}, $self->ID, $self->serialize, $timestamp)
  } else {
    # update
    $self->dbh->do("UPDATE sessions SET session_info=?, timestamp=? ".
		   "WHERE ID=?", {}, $self->serialize, $timestamp, $self->ID)
  }
  return 1
}

# cleaning
sub findOldSessions {
  my($self) = @_;
  $self->openDB;

  my $expired = time - $self->sessionTime;
  my $rows = $self->dbh()->selectall_arrayref("SELECT id FROM sessions ".
					      "WHERE timestamp < ?",{}, $expired);
  return map { $_->[0] } @$rows
}

sub clean {
  my($self, @ids) = @_;
  $self->openDB;
  foreach my $id (@ids) {
    $self->dbh()->do("DELETE FROM sessions WHERE ID=?",{},$id);
  }
  return 1
}

1;

__END__

=pod

=head1 NAME

CGI::Persist::DBI - A DBI interface to CGI::Persist

=head1 SYNOPSIS

  my $dbh = DBI->connect($dsn);
  my $cgi = CGI::Persist::DBI->new(dbh => $dbh,
				   sessionTime => 3600,
				   logFile => "/path/to/file")

=head1 DESCRIPTION

Enables you to store web-sessions in any database your DBI can understand. Gives you full access to the CGI interface.

See C<CGI::Persist> for more information

=head1 FUNCTIONS

=over 2

=item dbh

The database handle as an object.

=item driver

The driver DBI has to use.

=item db

The database DBI has to use.

=item host

The host DBI has to use.

=item user

The user DBI has to use.

=item pass

The pass(word) DBI has to use.

=back

No need to mention, I am sure, that if you specify dbh() validly, you do _not_ need to specify any of the others.

=head1 KNOWN BUGS

=over 4

=item * Database has gone away

Seems that sometimes when multiple instances of CGI::Persist::DBI live along side the database goes away... This only happens with MySQL databases (to my knowledge at least)

=back

=head1 AUTHOR

Hartog C. de Mik <hartog@2organize.com>

=cut
