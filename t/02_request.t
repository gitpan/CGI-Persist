use Test::More tests => 15;

use strict;

use_ok("CGI::Persist::File");

$ENV{REQUEST_METHOD}='GET';
$ENV{HTTP_USER_AGENT}='shell';
$ENV{REMOTE_ADDR}='127.0.0.1';

ok(FakeRequest( a => 1, b => 2, action => 'go', z => 4 ), "Fake request - OK");

my $p = CreateCGI();
ok(ref($p) eq "CGI::Persist::File", "CGI created - OK");

# add a parameter to the data.
$p->param('-name' => "Veggie", '-value' => "TRUE");
ok($p->param("Veggie") eq "TRUE", "parameter setting - OK");

# store something completely else --? doesn' work??
$p->data(MyName => "Hartog C. de Mik",
	 key => "0294202049522095");
ok($p->data("key") eq "0294202049522095", "data setting - OK");

#STORE ID
# read a parameter from the data.
my $id = $p->ID;

# store a multi-value parameter
undef $p;
FakeRequest("ID" => $id, q => 1, hoi => 1, hoi => 2, hoi => 3 );
$p = CreateCGI();
is(join(", ", ( $p->currentParam("hoi"))), "1, 2, 3", "Value array currentParam");

undef $p;
FakeRequest("ID" => $id);
$p = CreateCGI();
is(join(", ", ( $p->param("hoi"))), "1, 2, 3", "Value array param");


undef $p;
FakeRequest("ID" => $id, q => 1);
$p = CreateCGI();
ok($id eq $p->ID, "restored session - OK ($id = " . $p->ID .")");
ok($p->param("Veggie") eq "TRUE", "parameter remembered - OK");

undef $p;
FakeRequest(ID => $id, action => 'five', my_shirt => "is_groovy", d =>'6' );
$p = CreateCGI();
ok($id eq $p->ID, "restored session again - OK");
ok($p->param("q") eq "1", "parameter remembered - OK");

#should 
undef $p;
FakeRequest("ID" => $id  );
$p = CreateCGI();
ok($id eq $p->ID, "restored session one more time - OK");
ok($p->param("my_shirt") eq "is_groovy", "parameter remembered - OK");

#should be empty!
undef $p;
FakeRequest();
$p = CreateCGI(1);
ok($id ne $p->ID, "created new session - OK");
ok($p->sessionTime == 1, "sessionTime set to 1s - OK");
my $nid = $p->ID;

exit;

#----------------------------------
# 
# Generic test stuff
#

sub FakeRequest{
  my @all = @_;
  my ($key, $val);
  my $str = "";
  while (($key, $val, @all ) =  @all ){
    $str .= "&$key=$val";
  }

  $ENV{QUERY_STRING}="$str";
  $ENV{HTTP_USER_AGENT}='shell';
  $ENV{REMOTE_ADDR}='127.0.0.1';
  return 1;
}

sub CreateCGI{
  my $stime = shift || 900;

  no CGI::Persist::File;
  $INC{'CGI/Persist/File.pm'} = '';

  use CGI::Persist::File;
  $CGI::Persist::TEST = 1;

  my $p = CGI::Persist::File->new( root         => "./tmp",
				   prefix       => "t",
				   sessionTime  => $stime,
				   logFile      => "./tmp/test.log",
				   errorLogFile => "./tmp/error.log",
				 );
  return($p);
}
