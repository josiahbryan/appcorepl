
package AppCore::Web::MobileDetect;
{
	use strict;
	
	require Exporter;
	use vars qw/@ISA @EXPORT/;
	@ISA = qw(Exporter);
	
	@EXPORT = qw/
		ismobile
		isiphone 
		in_array
		isipad
	/;

	sub in_array {
		my ($arr,$search_for) = @_;
		my %items = map {$_ => 1} @$arr; # create a hash out of the array values
		return (exists($items{$search_for}))?1:0;
	}
	
	sub ismobile {
		my $useragent=lc(shift());
		my $is_mobile = '0';
	
		if($useragent =~ m/(android|up.browser|up.link|mmp|symbian|smartphone|midp|wap|phone)/i) {
			$is_mobile=1;
		}
		#print STDERR "ismobile: ua: '$useragent'\n";
	
		if((index($ENV{HTTP_ACCEPT},'application/vnd.wap.xhtml+xml')>0) || ($ENV{HTTP_X_WAP_PROFILE} || $ENV{HTTP_PROFILE})) {
			$is_mobile=1;
		}
	
		my $mobile_ua = lc(substr $ENV{HTTP_USER_AGENT},0,4);
		my @mobile_agents = ('w3c ','acs-','alav','alca','amoi','andr','audi','avan','benq','bird','blac','blaz','brew','cell','cldc','cmd-','dang','doco','eric','hipt','inno','ipaq','java','jigs','kddi','keji','leno','lg-c','lg-d','lg-g','lge-','maui','maxo','midp','mits','mmef','mobi','mot-','moto','mwbp','nec-','newt','noki','oper','palm','pana','pant','phil','play','port','prox','qwap','sage','sams','sany','sch-','sec-','send','seri','sgh-','shar','sie-','siem','smal','smar','sony','sph-','symb','t-mo','teli','tim-','tosh','tsm-','upg1','upsi','vk-v','voda','wap-','wapa','wapi','wapp','wapr','webc','winw','winw','xda','xda-');
	
		if(in_array(\@mobile_agents,$mobile_ua)) {
			$is_mobile=1;
		}
	
		if ($ENV{ALL_HTTP}) {
			if (index(lc($ENV{ALL_HTTP}),'OperaMini')>0) {
				$is_mobile=1;
			}
		}
	
		if (index(lc($ENV{HTTP_USER_AGENT}),'windows')>0) {
			$is_mobile=0;
		}
		return $is_mobile;
	}
	
	sub isiphone {
	
		my $useragent = @_;
		my $iphone=0;
		if (lc($useragent) =~ m/iphone/) {
			$iphone=1;
		}
		return $iphone;
	}
	
	sub isipad {
	
		my $useragent = @_;
		my $ipad=0;
		if (lc($useragent) =~ m/ipad/) {
			$ipad=1;
		}
		return $ipad;
	}
};
1;
