use Test::More tests => 5;

use strict;

use_ok("CGI::Persist::File");

my $id;
$ENV{REQUEST_METHOD}='GET';
$ENV{HTTP_USER_AGENT}='shell';
$ENV{REMOTE_ADDR}='127.0.0.1';

ok(FakeRequest( a => 1, b => 2, action => 'go', z => 4 ), "Fake request - OK");

my $p = CreateCGI();
ok(ref($p) eq "CGI::Persist::File", "CGI created - OK");

my $pid =  $p->ID;
$p->newSession;

ok($pid ne $p->ID, "new ID");

ok($p->clean($p->prefix . "-" . $pid) == -1, "cleaned self");

exit;

#----------------------------------
# 
# Generic test stuff
#

sub FakeRequest{
  my @all = @_;
  my ($key, $val);
  my $str;
  while (($key, $val, @all ) =  @all ){
    $str .= "&$key=$val";
  } 
  $ENV{'QUERY_STRING'}="$str";
  $ENV{HTTP_USER_AGENT}='shell';
  $ENV{REMOTE_ADDR}='127.0.0.1';
  return 1;
}

sub CreateCGI{
  my $stime = shift || 900;

  no CGI::Persist::File;
  use CGI::Persist::File;
  my $p = CGI::Persist::File->new( root => "./tmp",
				   prefix => "t",
				   sessionTime => $stime,
				   logFile     => "./tmp/test.log",
				 );
  return($p);
}
