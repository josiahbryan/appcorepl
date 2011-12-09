use strict;
package Boards::BanWords;
{
	use Storable qw/store retrieve/;
	use Time::HiRes qw/time/;
	
	my $DATA_FOLDER = '/opt/httpd-2.2.17/htdocs/appcore/mods/Boards/dg_phrase_list';
	
	my $WORD_CACHE = '/tmp/ban_words.dat';
	if(!-f $WORD_CACHE)
	{
# 		my @files = qw(
# 			goodphrases/weighted_general
# 			goodphrases/weighted_news
# 			goodphrases/weighted_general_danish
# 			goodphrases/weighted_general_dutch
# 			goodphrases/weighted_general_malay
# 			goodphrases/weighted_general_portuguese
# 			pornography/weighted
# 			pornography/weighted_french
# 			pornography/weighted_german
# 			pornography/weighted_italian
# 			pornography/weighted_portuguese
# 			nudism/weighted
# 			badwords/weighted_dutch
# 			badwords/weighted_french
# 			proxies/weighted
# 			warezhacking/weighted
# 		);
		use Data::Dumper;
		my @files;
		opendir(DIR,$DATA_FOLDER) || die "Cannot read directory $DATA_FOLDER";
		while(my $dir = readdir(DIR))
		{
			my $subdir = "$DATA_FOLDER/$dir";
			next if $dir =~ /(\.|\.\.)/ || !-d $subdir;
			print "Subdir: $subdir\n";
			open(SUBDIR, $subdir) || die "Cannot read subdir $subdir";
			my @sublist1 = `ls $subdir`; #readdir(SUBDIR);
			s/[\r\n]//g foreach @sublist1;
			@sublist1 = grep { /weighted/ } @sublist1; 
			@sublist1 = map { "$subdir/$_" } @sublist1;
			push @files, @sublist1;
			closedir(SUBDIR);
		}
		closedir(DIR);
		#die Dumper \@files;
	
	
		
		#@data = ('< test >,< word><40>','< alpha ><80>');
		use Data::Dumper;
		#print Dumper \@data;
		
		my @weight_list;
		
		my @master_words;
		my %word_lookup;
		
		my $word_id_counter = 0;
		
		foreach my $file (@files)
		{
			my @data = `cat $file`;
			print STDERR "Processing $file ...\n";
			
			s/([\r\n]|#.*$|\s+$)//g foreach @data;
			@data = grep {$_}@data;
			
			
			foreach my $line (@data)
			{
				my @tags = split/\,/, $line;
				my $last = pop @tags;
				my ($end,$value) = split/></, $last;
				push @tags, "$end>";
				$value =~ s/>$//g;
				#print Dumper \@tags, $value;
				
				next if $value+0 < 0;
					
				my @words;
				
				my $ref = { id => $word_id_counter ++, words => \@words, value => $value };
				
				foreach my $tag (@tags)
				{
					$tag =~ s/(^<|>$)//g;
					$tag = lc $tag;
					push @words, $tag;
					
					push @master_words, $tag;
					
					$word_lookup{$tag} = $ref;
				}
				
				#print Dumper \@words;
				push @weight_list, $ref;
			}
		}
		
		my $rx_val = '('.join('|',map { s/([\-\[\]\(\)])/\\$1/g; $_} @master_words).')';
		
		my $match_data_tmp = 
		{
			weight_list	=> \@weight_list,
			master_words	=> \@master_words,
			word_lookup	=> \%word_lookup,
			rx_val		=> $rx_val,
		};
		
		store $match_data_tmp, $WORD_CACHE;
		
		#print Dumper $match_data_tmp; #\@weight_list, \@master_words, \%word_lookup, $rx_val;
		print STDERR "Debug: Cache miss, stored $WORD_CACHE\n";
	
	}
	
	my $ta = time;
	my $match_data = retrieve $WORD_CACHE;
	
	my $load_time = time - $ta;
	
	#die Dumper $match_data;
	
	
	sub get_phrase_weight
	{
# 		my $user = AppCore::Common->context->user;
# 		return wantarray ? (0,0) : 0 if $user && $user->check_acl([qw/ADMIN Pastor/]);
	
	#	return (0,0);
		my $phrase = shift;
		my @match = $phrase =~ /$match_data->{rx_val}/gi;
		#die Dumper \@match;
		my %weights;
		my $lookup = $match_data->{word_lookup};
		foreach my $m (@match)
		{
			$m = lc $m;
			my $dat = $lookup->{$m};
			$dat->{m} = $m;
			#print STDERR "$m: ".Dumper($dat);
			$weights{$dat->{id}} = $dat;
		}
		
		#die Dumper \%weights;
		my $weight_sum = 0;
		
		my $lowercase_phrase = lc $phrase;
		
		# The words acutally used in weighting
		my @final_match;
		
		foreach my $dat (values %weights)
		{
			next if !$dat || !$dat->{words};
			my @list = @{$dat->{words}};
			my $firm_match = 1;
			
			#print STDERR Dumper($dat);
			
			# If not a firm match, proportianlly reduce score by amoutn matched
			my $total_words = scalar @list;
			my $count_matched = 0;
	
			my @matched;
			foreach my $word (@list)
			{
				$word =~ s/(^\s+|\s+$)//g;
				if(index($lowercase_phrase,$word) < 0 && index($lowercase_phrase,'nude') <0)
				{
					$firm_match = 0;
					last;
				}
				else
				{
					$count_matched ++;
					push @matched, $word;
				}
			}
		
			if($firm_match)
			{
				my $div = int($dat->{value} / scalar(@list));
				push @final_match, map { "$div points: '$_'" } @list;
				$weight_sum += $dat->{value};
			}
			else
			{
				my $percent = $count_matched / $total_words;
				my $total_score = $dat->{value} * $percent;
				my $div = int($total_score / scalar(@list));
				push @final_match, map { "$div points: '$_'" } @matched;
				$weight_sum += $total_score;
				#print "\tPartial match: $dat->{value} reduced to $total_score ($percent) ($count_matched / $total_words)\n";
			}
		}
		
		return wantarray ? ($weight_sum, \@final_match) : $weight_sum;
		
	}
	
	
# 	my $test = `cat t5.txt`;
# 	
# 	my $tb = time;
# 	my ($weight,$matched) = get_phrase_weight($test);
# 	
# 	my $match_time = time - $tb;
# 	
# 	print "Phrase: '$test'\nWeight: $weight\nMatch: \n  ".join("\n  ",@$matched)."\n";
# 	print "Load Time:  ".sprintf('%.03f',$load_time)."\nMatch Time: ".sprintf('%.03f',$match_time)."\n";
	
# 	foreach my $dat (@{$match_data->{weight_list}})
# 	{
# 		my @list = @{$dat->{words}};
# 		print STDERR $dat->{value}.": \t ".join(', ',@list)."\n";
# 	}
	
};

1;