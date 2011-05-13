package ThemePHC::VerseLookup;
{
	# Use to access the DbSetup package
	use Boards::Data;
	
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::DBTBL_VERSECACHE || 'verse_ref_cache',
		
		schema	=> 
		[
			{ field => 'lineid',			type => 'int', @Boards::DbSetup::PriKeyAttrs},
			{ field => 'verse_ref',			type => 'varchar(255)' },
			{ field => 'title',			type => 'text' },
			{ field => 'passage',			type => 'text' },
		],	
	});
	
	
	
	my %passage_rejects = map {$_=>1} qw/version see almost on at/;
	
	my $sth_get = __PACKAGE__->db_Main->prepare('select title,passage from '.__PACKAGE__->table.' where verse_ref=?');
	
	
	my $VERSE_URL_BASE = 'http://www.biblegateway.com/passage/?version=31&search=';
	use Digest::MD5 qw( md5_hex );
	use HTML::Entities;
	use LWP::Simple;

	sub get_verse_url
	{
		my $class = shift;
		my $ref = shift;
		
		my ($psg) = $ref =~ /(?:\d+\s*)?([A-Za-z]+)/;
		#print STDERR "$ref: $psg\n";
		
		return $ref if $passage_rejects{lc($psg)};
		
		return $ref if $ref =~ /([\.:]0\d|00$)/;
		
		$sth_get->execute($ref);
		if(my $data = $sth_get->fetchrow_hashref)
		{
			$data->{title} =~ s/\(New International Version\)/(NIV)/gi;
			my $raw = $data->{passage}.' - '.$data->{title};
			my $text = AppCore::Web::Common->html2text($raw); $text =~ s/\n//g;
			$text =~ s/(^\s+|\s+$)//g;
			$text =~ s/\s{2,}/ /g;
			$text =~ s/ - BibleGateway.com navigation$/ - $ref/g;
			#$text =~ s/&quot;/\\&quot;/g;
			# onmouseover='Tip(\"".encode_entities($text)."\")' onmouseout=\"UnTip()\"
			return "<a href='${VERSE_URL_BASE}${ref}' title='".encode_entities($text)."'>$ref<\/a>";
			
		}
		else
		{
			my $md5 = md5_hex($ref);
			open(FILE,">/tmp/$md5.ref");
			print FILE $ref;
			close(FILE);
			#/var/www/phc/
			my $lookup_script = AppCore::Web::Module::module_root_dir('ThemePHC') .'/internal/verse_lookup.pl';
			system("$lookup_script /tmp/$md5.ref &");
			
			return "<a href='${VERSE_URL_BASE}${ref}' title='Lookup ".encode_entities($ref)." on BibleGateway.com...'>$ref<\/a>";
			
		}
	}
	
	sub tag_verses
	{
		my $class = shift;
		my $textref = shift;
		
		my $ref = shift || $class;
		
		#print STDERR __PACKAGE__."::tag_verses(): text: ".$$textref."\n";
		#$text =~ s/((?:\d\s)?(?:[A-Za-z]+) (?:[0-9]+)(?:[:\.](?:[0-9]*))?(?:\s*-\s*(?:[0-9]*))?)/$ref->get_verse_url($1)/segi;
		$$textref =~ s/\b((?:Genesis|Gen|Ge|Gn|Exodus|Exo|Ex|Exod|Leviticus|Lev|Le|Lv|Numbers|Num|Nu|Nm|Nb|Deuteronomy|Deut|Dt|Joshua|Josh|Jos|Jsh|Judges|Judg|Jdg|Jg|Jdgs|Ruth|Rth|Ru|1 Samuel|1 Sam|1 Sa|1Samuel|1S|I Sa|1 Sm|1Sa|I Sam|1Sam|I Samuel|1st Samuel|First Samuel|2 Samuel|2 Sam|2 Sa|2S|II Sa|2 Sm|2Sa|II Sam|2Sam|II Samuel|2Samuel|2nd Samuel|Second Samuel|1 Kings|1 Kgs|1 Ki|1K|I Kgs|1Kgs|I Ki|1Ki|I Kings|1Kings|1st Kgs|1st Kings|First Kings|First Kgs|1Kin|2 Kings|2 Kgs|2 Ki|2K|II Kgs|2Kgs|II Ki|2Ki|II Kings|2Kings|2nd Kgs|2nd Kings|Second Kings|Second Kgs|2Kin|1 Chronicles|1 Chron|1 Ch|I Ch|1Ch|1 Chr|I Chr|1Chr|I Chron|1Chron|I Chronicles|1Chronicles|1st Chronicles|First Chronicles|2 Chronicles|2 Chron|2 Ch|II Ch|2Ch|II Chr|2Chr|II Chron|2Chron|II Chronicles|2Chronicles|2nd Chronicles|Second Chronicles|Ezra|Ezr|Nehemiah|Neh|Ne|Esther|Esth|Es|Job|Job|Jb|Psalm|Pslm|Ps|Psalms|Psa|Psm|Pss|Proverbs|Prov|Pr|Prv|Ecclesiastes|Eccles|Ec|Qoh|Qoheleth|Song of Solomon|Song|So|Canticle of Canticles|Canticles|Song of Songs|SOS|Isaiah|Isa|Is|Jeremiah|Jer|Je|Jr|Lamentations|Lam|La|Ezekiel|Ezek|Eze|Ezk|Daniel|Dan|Da|Dn|Hosea|Hos|Ho|Joel|Joe|Jl|Amos|Am|Obadiah|Obad|Ob|Jonah|Jnh|Jon|Micah|Mic|Nahum|Nah|Na|Habakkuk|Hab|Hab|Zephaniah|Zeph|Zep|Zp|Haggai|Hag|Hg|Zechariah|Zech|Zec|Zc|Malachi|Mal|Mal|Ml|Matthew|Matt|Mt|Mark|Mrk|Mk|Mr|Luke|Luk|Lk|John|Jn|Jhn|Acts|Ac|Romans|Rom|Ro|Rm|1 Corinthians|1 Cor|1 Co|I Co|1Co|I Cor|1Cor|I Corinthians|1Corinthians|1st Corinthians|First Corinthians|2 Corinthians|2 Cor|2 Co|II Co|2Co|II Cor|2Cor|II Corinthians|2Corinthians|2nd Corinthians|Second Corinthians|Galatians|Gal|Ga|Ephesians|Ephes|Eph|Philippians|Phil|Php|Colossians|Col|Col|1 Thessalonians|1 Thess|1 Th|I Th|1Th|I Thes|1Thes|I Thess|1Thess|I Thessalonians|1Thessalonians|1st Thessalonians|First Thessalonians|2 Thessalonians|2 Thess|2 Th|II Th|2Th|II Thes|2Thes|II Thess|2Thess|II Thessalonians|2Thessalonians|2nd Thessalonians|Second Thessalonians|1 Timothy|1 Tim|1 Ti|I Ti|1Ti|I Tim|1Tim|I Timothy|1Timothy|1st Timothy|First Timothy|2 Timothy|2 Tim|2 Ti|II Ti|2Ti|II Tim|2Tim|II Timothy|2Timothy|2nd Timothy|Second Timothy|Titus|Tit|Philemon|Philem|Phm|Hebrews|Heb|James|Jas|Jm|1 Peter|1 Pet|1 Pe|I Pe|1Pe|I Pet|1Pet|I Pt|1 Pt|1Pt|I Peter|1Peter|1st Peter|First Peter|2 Peter|2 Pet|2 Pe|II Pe|2Pe|II Pet|2Pet|II Pt|2 Pt|2Pt|II Peter|2Peter|2nd Peter|Second Peter|1 John|1 Jn|I Jn|1Jn|I Jo|1Jo|I Joh|1Joh|I Jhn|1 Jhn|1Jhn|I John|1John|1st John|First John|2 John|2 Jn|II Jn|2Jn|II Jo|2Jo|II Joh|2Joh|II Jhn|2 Jhn|2Jhn|II John|2John|2nd John|Second John|3 John|3 Jn|III Jn|3Jn|III Jo|3Jo|III Joh|3Joh|III Jhn|3 Jhn|3Jhn|III John|3John|3rd John|Third John|Jude|Jud|Revelation|Rev|Re|The Revelation) (?:[0-9]+)(?:[:\.](?:[0-9]*))?(?:\s*-\s*(?:[0-9]*))?)/$ref->get_verse_url($1)/segi;
		#(?:;\s*(?:[0-9]+)(?:[:\.](?:[0-9]*))?(?:\s*-\s*(?:[0-9]*))?)*
		
		#print STDERR "\n\n\n\nOutput:\n\n".$$textref."\n";
		
		#return $text;
	}
	
	
	#
	
	sub get_verse
	{
		my $class = shift;
		my $ref = shift;
		
		#my $cache = PHC::VerseLookup->by_field(verse_ref=>$ref);
		#return $cache if $cache;
		
		my $url = $VERSE_URL_BASE . $ref;
		
		print STDERR "Downloading $url\n";
		my $data = LWP::Simple::get($url);
		
		#print STDERR "Data: [$data]\n";
		
		my ($passage_title) = $data =~ /<h3>([^\<]+)<\/h3>/;
		my ($passage_text) = $data =~ /<div class="result-text-style-normal">((?:.|\n)+)<\/div>/;
		
		my $idx = index(lc $passage_text,'</div>');
		$passage_text = substr($passage_text,0,$idx);
		
		print STDERR "Got Title: $passage_title\n";
		
		my $cache = $class->create({verse_ref=>$ref,title=>$passage_title,passage=>$passage_text});
		return $cache;
	}
	
	
};
