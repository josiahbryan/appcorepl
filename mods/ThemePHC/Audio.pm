use strict;

package PHC::Recording;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> 'recordings',
		
		schema	=> 
		[
			{ field => 'recordingid',		type => 'int', @AppCore::DBI::PriKeyAttrs},
			{ field	=> 'uploaded_by',		type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'upload_timestamp',		type => 'timestamp' },
			{ field	=> 'title',			type => 'varchar(255)' },
			{ field	=> 'file_path',			type => 'text' },
			{ field	=> 'web_path',			type => 'text' },
			{ field	=> 'datetime',			type => 'datetime' },
			{ field	=> 'duration',			type => 'float' },
			{ field	=> 'published',			type => 'int(1)' },
			{ field => 'deleted',			type => 'int(1)' },
			{ field => 'sermon_track_num',		type => 'int' },
			{ field	=> 'sermon_file_path',		type => 'text' },
			{ field	=> 'sermon_web_path',		type => 'text' },
			{ field	=> 'sermon_duration',		type => 'float' },
		],	
	});
}


package PHC::Recording::Track;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> 'recording_tracks',
		
		schema	=> 
		[
			{ field => 'trackid',			type => 'int', @AppCore::DBI::PriKeyAttrs},
			{ field	=> 'recordingid',		type => 'int',	linked => 'PHC::Recording' },
			{ field	=> 'tracknum',			type => 'integer' },
			{ field	=> 'file_path',			type => 'text' },
			{ field	=> 'web_path',			type => 'text' },
			{ field	=> 'duration',			type => 'float' },
		],	
	});
}


package ThemePHC::Audio;
{
	# Inherit both the Boards and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		AppCore::Web::Module
		Content::Page::Controller
	};
	
	use Content::Page;
	
	use Boards::Data;
	
 	use JSON qw/decode_json encode_json/;
# 	use LWP::Simple qw/get/;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Audio Recordings','PHC Audio Recordings Database',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	use Data::Dumper;
	use DateTime;
	use AppCore::Common;
	#use JSON qw/to_json/;
	
	# to move bulk upload files
	use File::Copy;

	our $UPLOAD_TMP_WWW     = '/appcore/mods/ThemePHC/audio_upload_tmp';
	our $UPLOAD_TMP         = '/var/www/html'.$UPLOAD_TMP_WWW;
	our $RECORDING_WWW_ROOT = '/appcore/mods/ThemePHC/audio_recordings';	
	our $RECORDING_DOC_ROOT = '/var/www/html'.$RECORDING_WWW_ROOT;
	our $BULK_UPLOAD_ROOT   = '/home/phc/BulkTrackUpload/';	
	
	
	sub get_duration
	{
		my $file = shift;

		my $info = `exiftool $file | grep Duration`;
		my ($d) = $info =~ /:\s*(.*)$/;
		$d =~ s/\s+\(.*\)$//g;
		#print STDERR "d=$d\n";
		
		my $min;
		if($d =~ s/s\s*$//)
		{
			$min = $d/60;
		}
		else
		{
			my ($h,$m,$s) = split/:/, $d;
			$min = $h*60 + $m + $s/60;
		}
		
		#print STDERR "min=$min\n";
		return $min;
	}
	
	sub format_duration
	{
		my $dur = shift;
		my $format = shift || 0;
		#print STDERR "format_duration: at start, \$dur:'$dur', format:'$format'\n";
		#return "$dur:00 min" if $dur == int($dur);
		my $min = int($dur);
		my $sec = int(($dur - $min) * 60);
		my $hour = $min >= 60 ? $min/60 : 0;
		$min = int(($hour - int($hour)) * 60) if $hour;
		$hour = int($hour);
		if( $format )
		{
			$hour = ($hour<10?'0'.$hour:$hour);
			$min = ($min<10?'0'.$min:$min);
			$sec = ($sec<10?'0'.$sec:$sec);
			return join(':', $hour, $min, $sec);
		}
		#my $out = ($hour ? $hour.'hr ':'').($min ? $min:'').($sec ? 'm '.$sec.'s' : ($min?($hour ? 'min' : ' min'):''));
		my $out = ($hour ? $hour . ($min ? ":". ($min<10?"0$min":$min)." hr"  : " hr")  :
			  ($min  ? $min  . ($sec ? ":". ($sec<10?"0$sec":$sec)." min" : " min") : 
			  ($sec  ? "$sec sec" : "0 min"))); 
		#print STDERR "format_duration: output: '$out'\n";
		return $out;
		
	}
	
	sub get_recording_object($)
	{
		my $req = shift;
		my $recid = $req->{recordingid};
		my $recording;
		if(!$recid)
		{
			$recording = PHC::Recording->insert({
				uploaded_by	=> AppCore::Common->context->user,
				title		=> $req->{title},
				datetime	=> $req->{date}.' 09:00:00',
			});	
			print STDERR "get_recording_object: No ID in args, inserted ID '$recording'\n";
		}
		else
		{
			$recording = PHC::Recording->retrieve($recid);	
			print STDERR "get_recording_object: ID $recid in args, retrieved ID '$recording'\n";
		}
		
		return $recording;
		
	}
	
	sub create_new_track($)
	{
		my $recording = shift;
		my @tracks = PHC::Recording::Track->search(recordingid=>$recording);
		my $max = 0;
		foreach my $t (@tracks)
		{
			$max = $t->tracknum if $t->tracknum > $max;
		}
		
		$max ++;
		
		return PHC::Recording::Track->insert({
			recordingid	=> $recording,
			tracknum	=> $max,
		});
	}
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			PHC::Recording
			PHC::Recording::Track
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		return $self;
	};
	
	# Implemented from Content::Page::Controller
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
		# (but %%modpath%% will return /ThemeBryanBlogs for resources such as images)
		my $new_binpath = AppCore::Config->get("DISPATCHER_URL_PREFIX") . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		## Redispatch thru the ::Module dispatcher which will handle calling main_page()
		#return $self->dispatch($req, $r);
		return $self->audio_page($req,$r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	
# 	our $MissionsListCache = 0;
# 	sub clear_cached_dbobjects
# 	{
# 		#print STDERR __PACKAGE__.": Clearing navigation cache...\n";
# 		$MissionsListCache = 0;
# 	}	
# 	AppCore::DBI->add_cache_clear_hook(__PACKAGE__,'load_missions_list');
# 	
	sub check_sermon_mp3 
	{
		my $self = shift;
		my $recording = shift;
		
		return undef if !$recording->sermon_track_num;
		
		my $simple_filename = "recording_".$recording."-sermon.mp3";
			
		my $perm_sermon_mp3 = $RECORDING_DOC_ROOT."/$simple_filename";
		if(!-f $perm_sermon_mp3)
		{
			my $concat_file = $UPLOAD_TMP."/$simple_filename";
			my $sermon_track = $recording->sermon_track_num; 
			my @tracks = grep { $_->tracknum >= $sermon_track } PHC::Recording::Track->search(recordingid=>$recording);
			
			my @file_list = map {$_->file_path} @tracks;
			@file_list = map { s/^\/var\/www\/phc\/sermon_upload_tmp/$RECORDING_DOC_ROOT/g; $_ } @file_list;
			
			if(!-f $concat_file)
			{
				my $cmd = "cat ".join(' ',@file_list)." > $concat_file";
				print STDERR "cmd=$cmd\n";
				system($cmd);
			}
			
			my $calcd_duration = 0;
			$calcd_duration += $_->duration foreach @tracks;
			
			$recording->sermon_file_path($RECORDING_DOC_ROOT."/$simple_filename");
			$recording->sermon_web_path($RECORDING_WWW_ROOT ."/$simple_filename");
			$recording->sermon_duration($calcd_duration);
			$recording->update;
			
			my $tmp_www = $UPLOAD_TMP_WWW."/$simple_filename";
			print STDERR "Sermon MP3 didn't exist at $perm_sermon_mp3, so concat'd to $concat_file, tmp_www:$tmp_www, duration $calcd_duration, source tracks: ".join(', ', @file_list);
			
			return wantarray ? ($tmp_www,$calcd_duration,$concat_file) : $tmp_www;
		}
		
		#print STDERR "Sermon checked out, return web path: ".$recording->sermon_web_path."\n";
		#print STDERR "\$perm_sermon_mp3: '$perm_sermon_mp3'\n"; 
		
		return wantarray ? ($recording->sermon_web_path, 
				    $recording->sermon_duration, 
				    $recording->sermon_file_path)
			 
				 :  $recording->sermon_web_path;
	}
			
			
	
	use POSIX qw(strftime);
	sub format_rfc822_date 
	{
		my $iso_date = shift;
		my $epoch = iso_date_to_seconds($iso_date);
		return strftime("%a, %d %b %Y %H:%M:%S %z", localtime($epoch));
	}
	
	
			

	our $UPLOAD_ACL_GROUP = AppCore::User::Group->find_or_create(name => 'PHC-Can-Upload-Audio');
	my $UPLOAD_ACL = [$UPLOAD_ACL_GROUP->name];
	sub audio_page
	{
		#my ($class,$skin,$r,$page,$req,$path) = @_;
		my ($self,$req,$r) = @_;
		
		my $sub_page = $req->next_path;
		
		if($sub_page eq 'upload')
		{
			AppCore::AuthUtil->require_auth($UPLOAD_ACL);
			
			my $tmpl = $self->get_template('audio/upload.tmpl');
			
			my $date =  (split/\s/,date())[0];
			$tmpl->param(date => $date);
			
			my @parts = split/-/, $date;
			my $yr = substr($parts[0],2,2);
			my $title = 'Sunday AM '.$parts[1].'/'.$parts[2].'/'.$yr;
			$tmpl->param(title=>$title);
			
			return Content::Page::Controller->get_view('sub',$r)->output($tmpl);
		}
		elsif($sub_page eq 'publish')
		{
			AppCore::AuthUtil->require_auth($UPLOAD_ACL);
			my $recid = $req->{recordingid};
			my $recording = PHC::Recording->retrieve($recid);
			if(!$recording)
			{
				return $r->error("Sorry, '$recid' isn't a valid recording ID!"); 	
			}
			
			my @tracks = PHC::Recording::Track->search(recordingid=>$recording);
			if(!@tracks)
			{
				return $r->error("Tracks Required","You must upload at least one track inorder to publish this recording.");
			}
			
			my $dur = 0;
			$dur += $_->duration foreach @tracks;
			
			my $concat_file = $UPLOAD_TMP."/recording_".$recording.".mp3";
			my @file_list = map {$_->file_path} @tracks;
			my $cmd = "cat ".join(' ',@file_list)." > $concat_file";
			#print STDERR "cmd=$cmd\n";
			system($cmd);
			
			my $dur_check = get_duration($concat_file);
			
			$recording->file_path($concat_file);
			$recording->web_path($RECORDING_WWW_ROOT."/recording_".$recording.".mp3");
			$recording->duration($dur);
			$recording->published(1);
			$recording->sermon_track_num($req->{sermon_track_num} || 0);
			$recording->update;
			
			print STDERR "$concat_file: calculated duration: $dur, read duration: $dur_check\n";
			
			#use PHC::Web::Events;
# 			my $user = AppCore::Common->context->user;
# 			my $title_text = $recording->title;
# 			$title_text =~ s/Sunday AM/Sunday A.M./;
# 			my $ann = PHC::Web::Events->create_new_thread(PHC::WebBoard->by_field(folder_name=>'news'), 
# 			{
# 				location	=> '',
# 				subject		=> 'New Sermon Uploaded: '.$recording->title,
# 				poster_name	=> $user->display,
# 				poster_email	=> $user->email,
# 				alert_flag	=> 'green',
# 				comment		=> 'A new sermon has been added to the <a href="/phc/audio">Audio Page</a>: <b>'.$title_text.'</b>. Head on over to the <a href="/phc/audio">Audio Page</a> to listen online right from your computer!',
# 				_internal_	=> 1, # disable spam filtering
# 			});
			
			$self->send_talk_notifications($recording);
			
			# Clear our podcast cache 
			undef $self->{postcast_xml_cache};
			
			return $r->redirect($self->binpath);
			
			## Todo:
			# - find all tracks
			# - throw error if no tracks
			# - find duration
			# - set 'published' flag
		}
		elsif($sub_page eq 'del_track')
		{
			AppCore::AuthUtil->require_auth($UPLOAD_ACL);
			my $trackid = $req->{trackid};
			my $track = PHC::Recording::Track->retrieve($trackid);
			my $rec = $track->recordingid;
			if($rec->published)
			{
				return $r->output_data('text/html',"<html><head><script>parent.delete_track_cb(false,'The recording has already been published!')</script></head></html>\n");
				#exit;
			}
			$track->delete;
			return $r->output_data('text/html',"<html><head><script>parent.delete_track_cb(true)</script></head></html>\n");
		}
		elsif($sub_page eq 'add_track')
		{
			AppCore::AuthUtil->require_auth($UPLOAD_ACL);
			
			#print STDERR Dumper $req;
			
			if($req->{bulk_flag})
			{
				my $ftp_folder = $BULK_UPLOAD_ROOT;
				my @files = `ls $ftp_folder/`;
				s/[\r\n]//g foreach @files;
				#print STDERR Dumper(\@files);
				
				@files = grep { -f "$ftp_folder/$_" } @files;
				if(!@files)
				{
					print STDERR "INFO: $sub_page: No files in $ftp_folder to upload.\n";
					return $r->output_data('text/html',"<html><head><script>parent.do_upload(false);alert('No files found in the FTP BulkTrackUpload folder - did you put the tracks directly into the folder or did you make *another* folder inside the BulkTrackUpload folder and put them there? Check the FTP folder and try again.')</script></head></html>\n");
				}
				
				my $recording = get_recording_object($req);
				
				my $file_path = $UPLOAD_TMP."/recording_".($recording->id);
				my $file_url  = $RECORDING_WWW_ROOT."/recording_".($recording->id);
				system("mkdir -p $file_path");
				
				@files = sort @files;
				
				my @callback_list;
				foreach my $file (@files)
				{
					my $track = create_new_track($recording);
				
						
					my $t_num = $track->tracknum < 10 ? '0'.$track->tracknum: $track->tracknum;
					
					my $source = "$ftp_folder/$file";
					
					my $written_filename = "track_${t_num}.mp3";
					my $abs = "$file_path/$written_filename";
					
					print STDERR "Importing [$source] to [$abs]\n";
					move($source,$abs);
					
					my $duration = get_duration($abs);
					my $t_len = format_duration($duration);
					my $t_title = $recording->title. ' - Track '.$t_num;
					my $t_file = "$file_url/$written_filename";
					
					$track->file_path($abs);
					$track->web_path($t_file);
					$track->duration($duration);
					$track->update;
					
					my $cb = "parent._upload_cb($recording,'$t_num','$t_title','$t_len','$t_file')";
					#print STDERR "Callback: $cb\n";
					push @callback_list, $cb;
					
				}
				return $r->output_data('text/html',"<html><head><script>".join(';',@callback_list)."</script></head></html>"); 
				
				#print "Content-Type: text/html\n\n<html><head><script>parent.do_upload(false);alert('Still working on it-- not ready yet!')</script></head></html>\n";
				#exit;
			}
			
			
			my $filename = $req->{upload};
			#$skin->error("No Filename","No filename given") if !$filename;
			if(!$filename)
			{
				print STDERR "INFO: $sub_page: No file given to upload.\n";
				return $r->output_data('text/html',"<html><head><script>parent.do_upload(false);alert('You must select a file to upload.')</script></head></html>\n");
				
			}
			
			$filename =~ s/^.*[\/\\](.*)$/$1/g;
			my ($ext) = ($filename=~/\.(\w{3})$/);
			
			if(lc $ext ne 'mp3')
			{
				print STDERR "INFO: $sub_page: '$ext' is not an mp3 extension.\n";
				return $r->output_data('text/html',"<html><head><script>parent.do_upload(false);alert('Only MP3 files are allowed - the file you selected was a \"".uc($ext)."\" file.')</script></head></html>\n");
			}
			
			
			my $recording = get_recording_object($req);
			my $track = create_new_track($recording);
			
			my $t_num = $track->tracknum < 9 ? '0'.$track->tracknum: $track->tracknum;
			
			
			
			my $written_filename = "track_${t_num}.mp3";
			
			my $file_path = $UPLOAD_TMP."/recording_".($recording->id);
			my $file_url  = $RECORDING_WWW_ROOT."/recording_".($recording->id);
			system("mkdir -p $file_path");
			
			
			my $abs = "$file_path/$written_filename";
			
			print STDERR "Uploading [$filename] to [$abs], ext=$ext\n";
			
			my $fh = main::upload('upload');
			
			open UPLOADFILE, ">$abs" || warn "Cannot write to $abs: $!"; 
			binmode UPLOADFILE;
			
			while ( <$fh> )
			{
				print UPLOADFILE $_;
			}
			
			close(UPLOADFILE);
			
			my $duration = get_duration($abs);
			my $t_len = format_duration($duration);
			my $t_title = $recording->title. ' - Track '.$t_num;
			my $t_file = "$file_url/$written_filename";
			
			$track->file_path($abs);
			$track->web_path($t_file);
			$track->duration($duration);
			$track->update;
			
			
			if($req->output_fmt eq 'json')
			{
				my $b = {
					recordingid =>	$recording->id,
					tracknum =>	$t_num,
					title =>	$t_title,
					len =>		$t_len,
					file =>		$t_file,
				};
				my $json = encode_json($b);
				print STDERR "Add track JSON response: $json\n";
				return $r->output_data('application/json', $json);
			}
			
			my $cb = "parent._upload_cb($recording,'$t_num','$t_title','$t_len','$t_file')";
			#print STDERR "Callback: $cb\n";
			
			return $r->output_data('text/html',"<html><head><script>$cb</script></head></html>\n");
			#exit;
		}
		elsif($sub_page eq 'podcast.xml')
		{
			return $r->output_data('text/xml', $self->{postcast_xml_cache}) if $self->{postcast_xml_cache};
			
			my $tmpl = $self->get_template('audio/podcast.xml.tmpl');
			
			# datetime
			# current_year
			# loop: items
			#	- title, recording_page, mp3_url, description, datetime, mp3_url, mp3_bytes, duration
			
			my @audio = PHC::Recording->retrieve_from_sql(qq{
				published = 1 
				
				order by datetime desc
				
				limit 0, 52
			});#search(published=>1);
			
			# 0,52 = approx 1 year
			my $bin = $self->binpath;
			
			@audio = sort { $b->datetime cmp $a->datetime } @audio;
			foreach my $s (@audio)
			{
				$s->{$_} = $s->get($_) foreach $s->columns;
				$s->{bin} = $bin;
				
				my ($sermon_mp3, $sermon_dur, $sermon_file) = $self->check_sermon_mp3($s);
				my $mp3_www      = $sermon_mp3  ? $sermon_mp3  : $s->web_path;
				my $mp3_duration = $sermon_mp3  ? $sermon_dur  : $s->duration;
				my $mp3_file     = $sermon_file ? $sermon_file : $s->file_path;
			
				
				$s->{recording_page} = $self->module_url($s->id,1); # 1 = abs url
				$s->{mp3_url} = AppCore::Config->get('WEBSITE_SERVER'). $mp3_www;
				$s->{duration} = format_duration($mp3_duration, 1); # 1 = 00:00:00 format
				$s->{description} = 'Recording for '.$s->{title};
				$s->{mp3_bytes} = (stat($mp3_file))[7];
				
				$s->{datetime} = format_rfc822_date($s->{datetime});
				
				#$s->{dur} = format_duration(int($s->duration));
			}
			$tmpl->param(items => \@audio);
			
			my $datetime = @audio ? $audio[0]->{datetime} : undef;
			$tmpl->param(current_year => (localtime(time))[5] + 1900);
			$tmpl->param(datetime => $datetime); #format_rfc822_date($datetime));
			
			$self->{postcast_xml_cache} = $tmpl->output;
			return $r->output_data('text/xml', $self->{postcast_xml_cache});
			
		}
		elsif($sub_page)
		{
			my $recording = PHC::Recording->retrieve($sub_page);
			return $r->error('No Such Recording','Sorry, the recording ID you gave does not exist.') if !$recording;
			
			my ($sermon_mp3,$sermon_dur) = $self->check_sermon_mp3($recording);
			my $mp3_file     = $sermon_mp3 ? $sermon_mp3 : $recording->web_path;
			my $mp3_duration = $sermon_mp3 ? $sermon_dur : $recording->duration;
			
			my $tmpl = $self->get_template('audio/subpage.tmpl');
			
			$tmpl->param($_ => $recording->get($_)) foreach $recording->columns;
			$tmpl->param(mp3_file => $mp3_file);
			$tmpl->param(length   => format_duration(int($mp3_duration)));
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('Listen',$self->module_url($sub_page),0);
			$view->output($tmpl);
			return $r;
		}
		else
		{
			my $tmpl = $self->get_template('audio/main.tmpl');
			
			$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
			
			my $bin = $self->binpath;
			
			my $start = $req->{start} || 0;
			
			$start =~ s/[^\d]//g;
			$start = 0 if !$start || $start<0;
			
			
			my $count_sth = PHC::Recording->db_Main->prepare('select count(recordingid) as `count` from recordings where published=1 and deleted=0');
			$count_sth->execute;
			
			my $count = $count_sth->rows ? $count_sth->fetchrow_hashref->{count} : 0;
			
			my $length = 25;
			$start = $count - $length if $start + $length > $count;
			
			$tmpl->param(count => $count);
			$tmpl->param(pages => int($count / $length));
			$tmpl->param(cur_page => int($start / $length) + 1);
			$tmpl->param(next_start => $start + $length);
			$tmpl->param(prev_start => $start - $length);
			$tmpl->param(is_end => $start + $length == $count);
			$tmpl->param(is_start => $start <= 0);
			
			
			my @audio = PHC::Recording->retrieve_from_sql(qq{
				published = 1 
				and deleted = 0
				
				order by datetime desc
				
				limit $start, $length
			});#search(published=>1);
			@audio = sort { $b->datetime cmp $a->datetime } @audio;
			foreach my $s (@audio)
			{
				$s->{$_} = $s->get($_) foreach $s->columns;
				$s->{bin} = $bin;
				
				#$self->check_sermon_mp3($s);
				
				my @tracks = PHC::Recording::Track->search(recordingid=>$s);
				my @file_list = map {$_->web_path} @tracks;
				my @titles = map {$s->title.' - Track '.$_->tracknum} @tracks;
				my @artists = map { "" } @tracks;
				$s->{tracks} = join(',',@file_list);
				$s->{titles} = join(',',@titles);
				$s->{artists} = join(',',@artists);
				
				$s->{dur} = format_duration(int($s->duration));
			}
			$tmpl->param(audio => \@audio);
			
			
			return Content::Page::Controller->get_view('sub',$r)->output($tmpl);
		}
	}
	
		
	sub send_talk_notifications
	{
		my $self = shift;
		my $recording = shift;
		
		#my $folder = $post->folder_name;
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		my $post_url = "${server}/learn/listen/".$recording;
		
		my $data = {
			poster_name	=> 'PHC AV Team',
			poster_photo	=> 'https://graph.facebook.com/180929095286122/picture', # Picture for PHC FB Page
			poster_email	=> 'josiahbryan@gmail.com',
			comment		=> "A new audio recording has been added to the Podcasts/Audio Page - ".$recording->title.". Hear it at: $post_url",
			subject		=> "New Audio Recording: '".$recording->title."'",
		};
		
		my $talk_board_controller = AppCore::Web::Module->bootstrap('ThemePHC::BoardsTalk');
		my $talk_board = Boards::Board->retrieve(1); # id 1 is the prayer/praise/talk board
		
		my $talk_post = $talk_board_controller->create_new_thread($talk_board,$data);
		
		# Add extra data internally
		$talk_post->data->set('recordingid',$recording->id);
		$talk_post->data->set('post_url',$post_url);
		$talk_post->data->set('title',$recording->title);
		$talk_post->data->update;
		$talk_post->update;
		$talk_post->{_orig} = $recording;
		
		# Note: We call send_notifcations() on $talk_board_controller, but we set the {hook} arg to $self, 
		#       so it will call our facebook_notify_hook() to reformat the FB story args the way we want 
		#       them before uploading instead of using the default story format.
		#     - We 'really_upload' so we can use the hook - otherwise, it would delay until the crontab script ran, 
		#       which wouldn't call our hook.
		my @errors = $talk_board_controller->send_notifications('new_post',$talk_post,{really_upload=>1, hook=>$self}); # Force the FB method to upload now rather than wait for the poller crontab script
		if(@errors)
		{
			print STDERR "Error sending notifications of new audio recordingid $recording: \n\t".join("\n\t",@errors)."\n";
		}
			
	}
	
	sub facebook_notify_hook
	{
		my $self = shift;
		my $post = shift;
		my $form = shift;
		my $req = shift;
		
		# Create the body of the FB post
		my $post_url = $post->data->get('post_url');
		
		$form->{message} = $post->text; 
		#"New video from PHC: ".$post->data->get('description').". Watch it now at ".LWP::Simple::get("http://tinyurl.com/api-create.php?url=${phc_video_url}");
		 
		# Set the URL for the link attachment
		$form->{link} = $post_url;
		
		#my $image = $self->video_thumbnail($post);
		
		#my $pastor_user = AppCore::User->by_field(email => 'pastor@mypleasanthillchurch.org');
		
		my $orig_post = $post->{_orig};
		my $quote;
# 		if(!$orig_post)
# 		{
# 			$quote = "Read the full post at ".$post_url;
# 		}
# 		else
# 		{
# 			our $SHORT_TEXT_LENGTH = 60;
# 			my $short_len = AppCore::Config->get("BOARDS_SHORT_TEXT_LENGTH")     || $SHORT_TEXT_LENGTH;
# 			my $short = AppCore::Web::Common->html2text($orig_post->text);
# 			
# 			my $short_text  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
# 			
# 			$quote = "\"".
# 				 substr($short,0,$short_len) . "\"" .
# 				(length($short) > $short_len ? '...' : '');
# 		}
		
		my $image = 'http://cdn1.mypleasanthillchurch.org/appcore/mods/ThemePHC/images/phclogo-whitesq-50.jpg'; 
		
		# Finish setting link attachment attributes for the FB post
		$form->{picture}	= $image; # ? $image : 'https://graph.facebook.com/180929095286122/picture';
		$form->{name}		= $post->data->get('title');
		$form->{caption}	= "PHC AV Team";
		$form->{description}	= "Listen to the recording on the PHC Podcasts/Audio page under 'Watch and Learn'."; 
		#$post->data->get('description');
		
		# Update original post with attachment data
		my $d = $post->data;
		$d->set('has_attach',1);
		$d->set('name', $form->{name});
		$d->set('caption', $form->{caption});
		$d->set('description', $form->{description});
		$d->set('picture', $form->{picture});
		$d->update;
		$post->post_class('link');
		$post->update;
		
		# Replace the default Boards FB action with a link to the video post
		$form->{actions} = qq|{"name": "Listen at PHC's Site", "link": "$post_url"}|;
		
		# 
		
		# We're working with a hashref here, so no need to return anything, but we will anyway for good practice
		return $form;
	}

	

}

1;
