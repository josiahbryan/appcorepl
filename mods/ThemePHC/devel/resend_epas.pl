use strict;

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::User;
use AppCore::Web::Module;
use AppCore::Web::Common;
use ThemePHC::BoardsTalk;

my @list = qw/akthorn@freedomnet.net
akthorn@freedomnet.net
angjones79@aim.com
bdurbin@comcast.net
beanbarn@bright.net
behr319@hotmail.com
behr319@hotmail.com
behr81@hotmail.com
billensteinfarms@bright.net
billensteinfarms@bright.net
bobwiley57@gmail.com
bruce_davison@darke.k12.oh.us
bsmith@josiahbryan.com
bwilleford@bright.net
bwilleford@bright.net
c1doesit@yahoo.com
c1doesit@yahoo.com
caliss@anderson.edu
caliss@anderson.edu
casralass@yahoo.com
danielandashleybryan@gmail.com
daretters@hotmail.com
daretters@hotmail.com
dauberstock@yahoo.com
djessup@redgold.com
donandpat@aol.com
dpouder@hotmail.com
dreamergirl@woh.rr.com
drismiller@aol.com
dwilliam51@hotmail.com
dwilliam57@hotmail.com
dwilliam57@hotmail.com
faith08@gmail.com
gmak@example.com
grandpa7@peoplepc.com
grandpa7@peoplepc.com
humnongkalak@yahoo.co.id
humnongkalak@yahoo.co.id
janrasz@freedomnet.met
jasonpollitt@rocketmail.com
jbryan@productiveconcepts.com
jbryan@productiveconcepts.com
jenikayandbrian@yahoo.com
johnsporek@yahoo.com
josiahbryan@gmail.com
josiahbryan@gmail.com
jretrum@wcoil.com
jscholl065@gmail.com
jscholl065@gmail.com
kdavison@frankmiller.com
klaytonhd@yahoo.com
kristaspence@ymail.com
lcstump@bright.net
lcstump@bright.net
lgullett@bright.net
lstewart26@woh.rr.com
lstewart26@woh.rr.com
lzimmers@yahoo.com
malorie.dunlap@indwes.edu
malorie.dunlap@indwes.edu
manor6@omnicityusa.com
manor6@omnicityusa.com
matt30arnold@yahoo.com
mdenney@rcwifi.com
mdenney@rcwifi.com
nparsons@councilonruralservices.org
pricey@wildblue.net
rdjessup@aol.com
roberts39shop@yahoo.com
roberts39shop@yahoo.com
rpprice@isp.com
rpprice@isp.com
rtzimmers@embarqmail.com
rtzimmers@embarqmail.com
russ_tnt@yahoo.com
sarahkolp@yahoo.com
shawnnasee2010@aol.com
shawnnasee2010@aol.com
sheila64@bright.net
sherri_slaughter2000@yahoo.com
smwasson1984@yahoo.com
susan.bryan@gmail.com
susan.bryan5@gmail.com
tahampshire@yahoo.com
tahampshire@yahoo.com
teresa.zimmers@gmail.com/;

my %emails = map {$_=>1} @list;
my @final_list = sort {$a cmp $b} keys %emails;

#print Dumper \@final_list;
my $post = Boards::Post->retrieve(14445);

my $ctrl = ThemePHC::BoardsTalk->new;
$ctrl->send_email_alert($post, \@final_list);
