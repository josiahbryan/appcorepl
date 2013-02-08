use strict;
package AppCore::EmailQueue;
{
	use base 'AppCore::DBI';
	
	use Net::DNS;
	use Net::Domain qw(hostdomain);
	use Net::SMTP;
	
# 	BEGIN {
# 		eval('use Net::SMTP::TLS');# || warn "Unable to load Net::SMTP::TLS - Might not be able to send email thru GMail: $@" ; # required for relaying thru google
# 	}
	
	use MIME::Lite;

	__PACKAGE__->meta({
		table           => 'emailqueue',

		db		=> AppCore::Config->get("EMAIL_DB")      || 'appcore',
		table		=> AppCore::Config->get("EMAIL_DBTABLE") || 'emailqueue',
		
		schema  =>
		[
			{
				'field' => 'msgid',
				'extra' => 'auto_increment',
				'type'  => 'int(11)',
				'key'   => 'PRI',
				readonly=> 1,
				auto    => 1,
			},
			{       field   => 'sentflag',		type    => 'int(1)',    	default => 0,     null => 'NO' },
			{       field   => 'msg_from',		type    => 'varchar(255)',	default => '',    null => 'NO' },
			{       field   => 'msg_to',		type    => 'varchar(255)',	default => '',    null => 'NO' },
			{       field   => 'msg_cc',		type    => 'varchar(255)',	default => '',    null => 'NO' },
			{       field   => 'msg_subject',	type    => 'varchar(255)'	},
			{       field   => 'msg',		type    => 'longtext' 		},
			{       field   => 'result',		type    => 'varchar(255)'	},
			{       field   => 'timestamp',		type    => 'timestamp', 	default => 'CURRENT_TIMESTAMP', null => 'NO' },
		]
	});

	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update(__PACKAGE__);	
	}
	
	our %WasEmailed;
	sub reset_was_emailed
	{
		%WasEmailed = ();
	}
	
	sub was_emailed
	{
		my $class = shift;
		my $email = shift;
		return 1 if $WasEmailed{lc($email)};
	}
	
	sub send_email
	{
		my $class = shift;
		
		my ($list,$subject,$text,$high_import_flag,$from,%opts) = @_;
		
		$list = [$list] if !ref $list;
		
		#print STDERR "send_email(): list=".join(',',@$list),", subject=$subject, high_import_flag=$high_import_flag, text=[$text]\n";
		#print STDERR "send_email(): CATCH ALL: Sending to jbryan only.\n";
		#$list = ['jbryan@productiveconcepts.com'];
		if(!ref $text && AppCore::Config->get('EMAIL_ENABLE_DEBUG_FOOTER'))
		{
			my $host = `hostname`;
			$host =~ s/[\r\n]//g;
		
			$text .= qq{
	
--
$0($$)
Server: $host
}
.($ENV{REMOTE_ADDR} ? "IP: $ENV{REMOTE_ADDR}\n":"")
.($ENV{HTTP_REFERER} ? "Referer: $ENV{HTTP_REFERER}\n":"")
		}
		
		$from ||= AppCore::Config->get('EMAIL_DEFAULT_FROM') || AppCore::Config->get('WEBMASTER_EMAIL');
		#print "From:$from\nTo:$to\nSubj:$subject\nText:$text\n";
		#print_stack_trace();
	
		my $email_tmp_dir = AppCore::Config->get('EMAIL_TMP_DIR') || '/var/spool/appcore/mailqueue';
		
		my @msg_refs;
		
		foreach my $to (@$list)
		{
			$WasEmailed{lc($to)} = 1;
				
			my $str = undef;
			if($opts{raw_mime})
			{
				$str = $text;
				#warn "Options said raw_mime";
			}
			elsif(UNIVERSAL::isa($text, 'MIME::Lite'))
			{
				$str = $text->as_string;
				#warn "Text was MIME::Lite, called as_string";
			}
			else
			{
				my $msg = MIME::Lite->new(
						From    =>$from,
						To      =>$to,
						'Reply-To'=>$from,
						CC      =>$opts{cc} || '',
						Subject =>$subject,
						Type    =>'multipart/mixed'
						);
			
				### Add parts (each "attach" has same arguments as "new"):
				$msg->attach(Type       => 'TEXT',
					     Data       => $text);
	
				$msg->attach(%{$_}) foreach @{ $opts{attachments} || [] };
				
				#$from =~ s/.*?<?([\w_\.]z+\@[.^\>]*)/$1/g;
			
				$str = $msg->as_string;
				#warn "Composed string implicitly";
			}
			
			#die "String: $str\n";
		
			$str =~ s/Subject:/Importance: high\nX-MSMail-Priority: urgent\nX-Priority: 1 (Highest)\nSubject:/g if $high_import_flag;
			#die $str;
			
			if(length($str) > 1024*512) # Larger than half a meg
			{
				my $uuid = `uuidgen`;
				$uuid =~ s/[\r\n-]//g;
				my $file = $email_tmp_dir . '/'. $uuid . '.eml';
				
				#print STDERR "(case2) Debug: Attempting to save to $file...\n";
				if(open(FILE,">$file"))
				{
					print FILE $str;
					close(FILE);
					
					$str = "#file:$file";
					
					#print STDERR "(case2) Debug: Wrote file, new str: '$str'\n";
				}
				else
				{
					warn "(case2) Couldn't write to $file: $!, sending using raw database blob";
				}
			}
		
			eval
			{
				#$q_ins->execute($from,$to,$str,$subject);
				push @msg_refs, AppCore::EmailQueue->insert({
					msg_subject	=> $subject,
					msg_from	=> $from,
					msg_to		=> $to,
					msg_cc		=> $opts{cc} || '',
					msg		=> $str,
				});
			};
			
			#print STDERR "$str, $from, $to, LEN:".(length($str)/1024)."KB\n$@" if $@;
			die $@ if $@;
		}

		return wantarray ? @msg_refs : shift @msg_refs;
	}
	
	our $DEBUG = 0;
	sub send_all
	{
		my $self = shift;
		my @unsent = $self->search(sentflag => 0);
		
		#print STDERR AppCore::Common::date().": Email Queue: ".scalar(@unsent)." messages.\n" if $DEBUG;
		
		foreach my $ref (@unsent)
		{
			print STDERR AppCore::Common::date().": Email Queue: transmitting $ref\n" if $DEBUG;
			$ref->transmit;
			print STDERR AppCore::Common::date().": Email Queue: DONE transmitting $ref\n" if $DEBUG;
		}
	}
	
	sub transmit
	{
		my $self = shift;
	
		my $data = $self->msg;
		if($data =~ /^#file:(.*)$/)
		{
			if(!-f $1)
			{
				print STDERR "File $1 does not exist, not sending email.\n";
				$self->sentflag(1);
				$self->result("Error: File $1 doesn't exist");
				print STDERR "MsgID $self: ".$self->result."\n";
				$self->update;
				return;
			}
		}

		my ($user,$domain) = split /\@/, $self->msg_from;
		$domain =~ s/>$//g;

		$domain = lc $domain;
		
		my $prof = AppCore::Config->get('EMAIL_DOMAIN_CONFIG')->{$domain};
		
		if(!$prof)
		{
			# Just IGNORE this message because we'll assume another script will 
			# run with a different config that *will* handle this domain - no harm in just ignoring it.
# 			$self->sentflag(1);
 			$self->sentflag(0);
# 			$self->result("Error: Domain $domain not in list of allowed domains to send from");
# 			print STDERR "MsgID $self: ".$self->result." (from:".$self->msg_from.")\n";
			$self->result("Warn: Ignoring, domain $domain not in list of allowed domains to send from");
 			print STDERR "MsgID $self: ".$self->result." (from:".$self->msg_from.")\n";
 			$self->update;
			return;
		}
		
		# If config says its allowed (a true value) but no config, assume direct relay
		$prof = { server => 'localhost' } if !ref $prof;
		
		#print STDERR "Debug: Profile domain: $domain, using server: '$prof->{server}'\n";
		
		
		my $pkg = $prof->{pkg};
		if(!$pkg && 
		    $prof->{server} ne 'localhost')
		{
			$self->sentflag(1);
			$self->result("Error: Invalid config for $domain - no sender package in custom config");
			print STDERR "MsgID $self: ".$self->result."\n";
			$self->update;
			return;
		}

		my $smtp;

		if($prof->{server} eq 'localhost')
		{
			$self->sentflag(1);
			$self->result("OK: Sent via direct relay");
			$self->update;
			
			my $data = $self->msg;
			if($data =~ /^#file:(.*)$/)
			{
				print STDERR "Debug: Reading file $1\n" if $DEBUG;
				my $file = $1;
				open(FILE,"<$file");
				my @buffer;
				push @buffer, $_ while $_ = <FILE>;
				close(FILE);
				$data = join '', @buffer;
				#unlink($file);
				system("mv $file /var/spool/appcore/mailsent");
			}
			my ($tuser,$tdomain) = split /\@/, $self->msg_to;
			$tdomain =~ s/>$//g;

			$self->_relay($tdomain,$self->msg_from,$self->msg_to,$data);
			print STDERR "Relayed directly thru localhost, t.user: $tuser, t.domain: $tdomain\n" if $DEBUG;
			return;
		}
		
		#print STDERR "Fox\n";
		my %args;
		eval{
		
			#print STDERR "Debug: Pkg: $pkg, server: $prof->{server}, port: $prof->{port}, user: $prof->{user}, pass: $prof->{pass}, domain: $domain\n";
			
			eval('use '.$pkg);
			 
			#die "Unable to load $pkg - Unable to send email thru $prof->{server}: $@" ; # required for relaying thru google
			
			%args = (
				Port  => $prof->{port} || 25,
				Hello => $domain,
				Debug => $DEBUG
			);
			#if($pkg eq 'Net::SMTP::TLS')
			{
				$args{User}     = $prof->{user} || 'notifications';
				$args{Password} = $prof->{pass} || 'Notify1125';
			}
			
 			#use Data::Dumper;
			#print STDERR Dumper \%args;
				
			$smtp = $pkg->new($prof->{server}, %args); # connect to an SMTP server
		};
		
		if(!$smtp || $@)
		{
			my $err = $@;
			$self->sentflag(1);
			$self->result("Error: Unable to send: ".($err ? $err : "$pkg didn't connect for some reason"));
			use Data::Dumper;
			print STDERR "MsgID $self: ".$self->result."\n".Dumper(\%args);
			$self->update;
			return;
		}

		$self->sentflag(1);
		$self->result("OK: Sent thru ".$prof->{server}.":".($prof->{port}||25)." via $pkg");
		$self->update;

		if($smtp->can('auth') && $prof->{user})
		{
			print STDERR "[DEBUG] Authenticating as user '$prof->{user}', password '$prof->{pass}'\n" if $DEBUG;
			if(!$smtp->auth($prof->{user},$prof->{pass}))
			{
				$self->sentflag(1);
				$self->result("Error logging into mail server: ".$smtp->message().($@? " ($@)":""));
				print STDERR "MsgID $self: ".$self->result."\n";
				$self->update;
				
				return;
			}
		}

		my @recips = ($self->msg_to);
 		my @cc = split(/,/, $self->msg_cc);
 		s/(^\s+|\s+$)//g foreach @cc;
		push @recips, @cc;

		foreach my $recip (@recips)
		{
			my $required_from = $prof->{user} =~ /@/ ? $prof->{user} : $prof->{user}.'@'.$domain;
			print STDERR "[DEBUG] Domain: '$domain', To: $recip, From: ".$self->msg_from.", Server: $prof->{server}:$prof->{port}, Req: $required_from\n" if $DEBUG;
				#user: $prof->{user}, pass: $prof->{pass}, port: $prof->{port}\n";

			$smtp->mail($required_from);

			#$smtp->to($self->msg_to); # recipient's address
			$smtp->to($recip); # recipient's address
			$smtp->data(); # Start the mail

			my $data = $self->msg;
			if($data =~ /^#file:(.*)$/)
			{
				print STDERR "Debug: Reading file $1\n" if $DEBUG;
				my $file = $1;
				open(FILE,"<$file");
				while($_ = <FILE>)
				{
					s/From: .*$/From: $required_from/ if $domain eq 'productiveconcepts.com';
					#print "[DATA] $_\n";
					$smtp->datasend($_);
				}
				close(FILE);
				#unlink($file);
				system("mv $file /var/spool/appcore/mailsent");

				# Wierd, I know - but since we deleted the data file, there really is no point in keeping this record around in the database either...
				#$self->delete;
			}
			else
			{
				$data =~ s/From:.*\n/From: $required_from\n/i if $domain eq 'productiveconcepts.com';
				#print "[DATA] $data\n";
				$smtp->datasend($data);
			}
			$smtp->dataend();
		}
		
		print "Done.\n" if $DEBUG;
		#exit if $DEBUG;
	}


	sub _relay
	{
		my $self = shift;
		
		my ($domain,$from,$target,$msg) = @_;
	
		my $rr;
	
		my $res = Net::DNS::Resolver->new;
		my @mx = mx($res, $domain);
		@mx = ($domain) if !@mx;
		if(my $mx_list = AppCore::Config->get('EMAIL_MX_OVERRIDES')->{$domain})
		{
			@mx = @$mx_list;
		}
		#my $success = 0;
	
		print STDERR "Debug: from:$from, target:$target, domain:$domain, mx=[".join(',',@mx)."]\n" if $DEBUG;
	
		# Loop through the MXs.
		foreach $rr (@mx)
		{
			my $exch = ref $rr ? $rr->exchange : $rr;
			print STDERR "Debug: rr loop, exch=$exch\n" if $DEBUG;
			my $client = new Net::SMTP($exch, 
				#Hello => 'mybryanlife.com', 
				#Hello => 'mypleasanthillchurch.org',
				Hello => 'productiveconcepts.com',
				#Debug=>$DEBUG) || next;
				Debug=>1) || next;
			$client->mail($from), #'jbryan@productiveconcepts.com');
			$client->to($target);
			$client->data($msg);
			$client->quit;
	
			return 1;
			#last;
		}
		return 0;
	}
	


};
1;
