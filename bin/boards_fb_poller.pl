#!/usr/bin/perl

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::User;
use AppCore::Web::Module;
use LWP::Simple qw/get/;
use JSON qw/decode_json/;
use Boards::Data;
use Boards;
use AppCore::Web::Common;
# For making MD5's of FB userids for storage photos
use Digest::MD5 qw/md5_hex/;

use strict;

# Make sure we're only running one polling instance at a time
use Fcntl qw(:flock);
flock(DATA, LOCK_EX|LOCK_NB) or die "Already running";

system("date >> /tmp/boards_fb_poller.crontab");

print date().": $0 Starting...\n";

# Disable spam filtering for this script
$Boards::SPAM_OVERRIDE = 1;

my $controller = Boards->new;

my %seen_feed; # flag feeds we've already synced so we dont duplicate post

# Upload all new posts to FB from Boards
my @posts = Boards::Post->retrieve_from_sql(q{deleted=0 and extra_data like '%"needs_uploaded":1%'});

print date().": $0 Uploading posts to FB...\n" if @posts;
foreach my $post (@posts)
{
	next if ! $post->boardid->fb_sync_enabled;
	next if   $post->data->get('user_said_no_fb');
	
	my $noun = 'post';
	if($post->top_commentid && $post->top_commentid->id)
	{
		$noun = 'comment';
		next if $post->top_commentid->deleted;
	}
	
	# Upload the post to FB
	if($controller->get_controller($post->boardid)->notify_via_facebook('new_'.$noun, $post, { really_upload=>1 }))
	{
		# Clear the 'needs uploaded' flag
		$post->data->set('needs_uploaded',0);
		$post->data->update;
	}
}

#die "Just testing - not going to run download yet";

# Now iterate over all boards and attempt to pull down new posts/comments from FB
my @boards = Boards::Board->search(fb_sync_enabled => 1, enabled => 1);

print date().": $0 Checking ".scalar(@boards)." boards for new posts from FB...\n" if @boards;
foreach my $board (@boards)
{
	#next if !$board->fb_sync_enabled;
	
	#next if $board->id == 4;
	
	my $fb_feed_id      = $board->fb_feed_id;
	my $fb_access_token = $board->fb_access_token;
	
	if(!$fb_feed_id || !$fb_access_token)
	{
		print STDERR "Not syncing '".$board->title."' - no FB Feed ID or Access Token.\n";
		next; 
	}
	
	my $feed_url = "https://graph.facebook.com/${fb_feed_id}/feed?access_token=${fb_access_token}";#&limit=999";
	
	if($seen_feed{$feed_url})
	{
		print STDERR "Not syncing '".$board->title."' - already synced feed $fb_feed_id to board '".$seen_feed{$feed_url}->title."'\n";
		next;
	}
	
	$seen_feed{$feed_url} = $board;
	
	update_board($board,$feed_url);
}

print date().": $0 Finished\n\n";

###############################################################################################3

sub lookup_user
{
	my ($poster_fb_id,$name) = @_;
	my $user;
	AppCore::User->by_field(fb_userid => $poster_fb_id) if $poster_fb_id;
	if(!$user)
	{
		#print STDERR "lookup_user(): Mark1: [$name]\n";
		$user = AppCore::User->by_field(display => $name);
	}
	if(!$user && $name =~ /(\w+?)\s+(\w+)/) # Try to stem common names
	{
		# TODO is their a module to do this already??
		my $last = $2;
		my $first = lc $1;
		if($first eq 'matthew')
		{
			$first = 'Matt';
		}
		
		$user = AppCore::User->by_field(display => "$first $last");
	}
	if(!$user && $name =~ /(\w+?)\s+\w+\s+(\w+)/) # remove the middle name and re-search
	{
		#print STDERR "lookup_user(): Mark2: [$1 $2]\n";
		$user = AppCore::User->by_field(display => "$1 $2");
	}
	if(!$user && $name =~ /(\w+)\s+(?:\w+\s+)?\w+-(\w+)/) # try the second last name (the first of the hyphenated last name would be tried in the middle name regex)
	{
		#print STDERR "lookup_user(): Mark3: [$1 $2]\n";
		$user = AppCore::User->by_field(display => "$1 $2");
	}
	return $user;
}
	

sub update_board
{
	my $board = shift;
	my $feed_url = shift;
	
	use LWP::Simple;
	my $json = LWP::Simple::get($feed_url);
	die "Error getting $feed_url: $@" if $@;
	my $feed_hash;
	
	eval { $feed_hash = decode_json($json); };
	die "Error parsing json: $@\nJSON: $json\nFeed URL: $feed_url\nScript stopped" if $@;
	
	my $feed_list = $feed_hash->{data};
	
	my $board_controller = $controller->get_controller($board);
	
	foreach my $fb_post (@$feed_list)
	{
		my $external_id = $fb_post->{id};
		next if $external_id eq '180929095286122_150297708396755'; # Bad UTF8 encoding, buggers FastCGI in output, so skip for now
		
		my $post = Boards::Post->by_field(external_id => $external_id, deleted => 0);
		
		my $post_is_new = 0;
		if(!$post)
		{
			my $fb_type = $fb_post->{type};
			$fb_type = 'photo' if $fb_type eq 'image';
#   			print STDERR "[DEBUG] Test, New Post (FB ID $external_id): By ".$fb_post->{from}->{name}.": '$fb_post->{message}' (Type: $fb_type)\n";
#   			print STDERR Dumper $fb_post; # if $fb_type ne 'photo' && $fb_type ne 'status' && $fb_type eq 'link';# && !$fb_post->{message}; 
# # 			#$fb_post->{type} eq 'photo' && !$fb_post->{message} && !$fb_post->{caption};
#  			next;
			
			my $poster_fb_id = $fb_post->{from}->{id};
			my $poster_photo_url = "https://graph.facebook.com/" . $poster_fb_id . "/picture";
			
			# Attempt to locate a local user matching the Facebook user
			my $user = lookup_user($poster_fb_id, $fb_post->{from}->{name});
			$poster_photo_url = download_user_photo($user, $poster_photo_url, $poster_fb_id);
			
			my $message = $fb_post->{message};
			if(!$message)
			{
# 				if($fb_post->{caption})
# 				{
# 					#$message = "<span class=name>" . $fb_post->{from}->{name} ."</span> "
# 					$message = "uploaded <a href='$fb_post->{link}'>$fb_post->{caption}</a> to <b><a href='$fb_post->{link}'>$fb_post->{name}</a></b> on <i>Facebook</i>";
# 				}
# 				else
# 				{
# 					$message = $fb_post->{description};
# 				}
			}
			
			# Create a set of arguments for create_new_thread()
			my $data = {
				poster_name	=> $fb_post->{from}->{name},
				poster_photo	=> $poster_photo_url,
				poster_email	=> $user ? $user->email : undef,
				comment		=> $message,
				post_class	=> $fb_type eq 'status' ? 'post' : $fb_type,
				system_content	=> !$message ? 1:0,
			};
			
			if($fb_type eq 'photo')
			{
# 				$data->{comment} .= qq{
# 					<hr size=1 class='post-attach-divider'>
# 					<a class='image-link' href="$fb_post->{link}"><img src="$fb_post->{picture}" border=0><span class='overlay'></span></a>};
			}
			elsif($fb_type eq 'link')
			{
# 				if($data->{comment} !~ /http:/)
# 				{
# 					$data->{comment} .= "<br>\nLink: $fb_post->{link}\n";
# 				}
			}
			elsif($fb_type eq 'video')
			{
				if($data->{comment} !~ /http:/)
				{
					$data->{comment} .= "<br>\nWatch at $fb_post->{link}\n"; 	
				}
			}
			
 			#print STDERR "[DEBUG] Data set: ".Dumper($data, $fb_post)."\n\n\n" if $fb_type eq 'link' && $fb_type ne 'status';
 			#next;
			
			
			# Use Boards to create a new thread
			$post = $board_controller->create_new_thread($board, $data, $user);
			
			#print STDERR "Debug: fb type: '$fb_type', in args:'$data->{post_class}', post class:'".$post->post_class."'\n";
			
			# Apply Facebook-specific data/fields that create_new_thread doesnt know about
			my $create_time = normalize_timestamp($fb_post->{created_time});
			$post->timestamp($create_time);
			
			my $update_time = normalize_timestamp($fb_post->{updated_time} ? $fb_post->{updated_time} : $fb_post->{created_time});
			$post->updated_time($update_time);
			
			# Flag it as from FB and store the FB Post ID for future reference
			$post->external_id($external_id);
			$post->external_source('Facebook');
			
			if($fb_type eq 'photo' ||
			   $fb_type eq 'video' ||
			   $fb_type eq 'link')
			{
				my $d = $post->data;
				$d->set($_, $fb_post->{$_}) foreach qw(
					picture
					link
					name
					caption
					message
					description
					icon
				);
				$d->set('has_attach', 1);
				$d->update;
			}
			
			if($fb_type eq 'photo')
			{
				$post->external_url($fb_post->{link});
			}
			else
			{
				my ($user,$post_num) = split /_/, $external_id;
				if($user && $post_num)
				{
					$post->external_url('https://www.facebook.com/' . $user . '/posts/' . $post_num);
				}
			}
			
			$post->data->set('fb_data', $fb_post);
			$post->data->update;
			
			$post->update;
			
			$post_is_new = 1;
			
			my $url = AppCore::Config->get('WEBSITE_SERVER') . "/boards/".$board->folder_name."/".$post->folder_name;
			print "Created post from facebook - # $post - '".$post->subject."' - $url\n";
		}
		else
		{
			#print "Found valid post in our database from facebook - # $post - '".$post->subject."'\n";
		}
		
		if($post->external_source eq 'Facebook' &&
			$post->id != 14294)  # Dont test this post - for some reason, it ALWAYS shows as new...
		{
			# Since this post was created FROM facebook (and not by us creating a post then uploading it to FB),
			# we will check the update timestamp and attempt to update our local copy of the message if the
			# facebook post has been recently updated
			my $fb_time = $fb_post->{updated_time};
			$fb_time = $fb_post->{created_time} if !$fb_time;
			$fb_time =~ s/^([^T]+)T([^\+\-]+)/$1 $2/g;
			if(!$post_is_new && ($post->updated_time cmp $fb_time) < 0) # FB is newer...
			{
				# Sync post message 
				my $msg = $fb_post->{message};
				
				# Try to guess if HTML is really just text
				$msg = text2html($msg) if !might_be_html($msg);
				$msg = trim_spaces($msg);
				
				if(trim_spaces($post->text) ne $msg)
				{
					$post->text($msg);
					$post->updated_time($fb_time);
					$post->update;
					
					my $url = AppCore::Config->get('WEBSITE_SERVER') . "/boards/".$board->folder_name."/".$post->folder_name;
					print "Updated post text from facebook - # $post - '".$post->subject."' - $url\n";
					print "DEBUG[A]: [".$post->text."]\n";
					print "DEBUG[B]: [".$msg."]\n";
				}
			
			}
		}
		
		# Check for likes on this post
		my $like_hash  = $fb_post->{likes}   || {};
		my $like_count = $like_hash->{count} || 0;
		my $like_list  = $like_hash->{data}  || [];
		if($like_count > 0)
		{
			my @count = Boards::Post::Like->search(postid => $post->id);
			if(@count != $like_count)
			{
				# Do a bit of funny math..
				my $diff = $like_count - @count;
				my @list = @$like_list;
				$diff -= @list;
				
				# Create anonymous likes
				Boards::Post::Like->insert({postid => $post}) for 0 .. $diff - 1;
				print "Post: Created ($diff) anonymous likes on post '".$post->subject."' - existing ".scalar(@count)." likes, ".scalar(@list)." named likes, total likes on FB $like_count\n" if $diff > 0;
				
				#die "terminating test\n";
				# Now create named likes
				foreach my $named_like (@list)
				{
					# Attempt to locate a local user matching the Facebook user
					my $user = lookup_user($named_like->{id}, $named_like->{name});
					
					my @result;
					if($user && $user->id)
					{
						# Try to find based on userid
						@result = Boards::Post::Like->search(postid => $post->id, userid => $user->id);
					}
					else
					{
						# Try to find based on just the name of the user
						@result = Boards::Post::Like->search(postid => $post->id, name => $named_like->{name});
					}
					
					# Couldnt find a "like" for this name/user - so create one
					if(!@result)
					{
						my $poster_photo_url = "https://graph.facebook.com/" . $named_like->{id} . "/picture";
						$poster_photo_url = download_user_photo($user, $poster_photo_url, $named_like->{id});
						
						my $ref = Boards::Post::Like->insert({
							postid	=> $post,
							userid	=> $user,
							name	=> $named_like->{name},
							email	=> $user ? $user->email : '',
							photo	=> $poster_photo_url,
						});
						
						my $noun = $post->top_commentid && $post->top_commentid->id ? 'comment' : 'post';
						
						#use Data::Dumper;
						#print STDERR "Debug: ref: $ref, post: $post, Dump:".Dumper($ref).", tmp:".$ref->postid."\n";
						
						#$board_controller->send_notifications('new_like', $ref, {noun=>$noun});
						
						print "Post: Created named like from '$named_like->{name}' (user? $user) on post '".$post->subject."\n";
					}
				}
			}
		}
		
		# Now try to pull down list of comments onto the $post
		
		my $comments_hash = $fb_post->{comments} || {};
		my $cmt_list = $comments_hash->{data} || [];
		foreach my $cmt_ref (@$cmt_list)
		{
			# Note: A Comment posted here THEN uploaded to FB will NEVER appear in the comments list
			# (until the FB api changes) because we upload comments as new top-level stories on FB.
			# So this is only one way - create new comments on our posts based on comments from FB
			my $fb_cmtid = $cmt_ref->{id};
			my $cmt = Boards::Post->by_field(external_id => $fb_cmtid, deleted => 0);
			
			# If the top_commentid has been deleted in software (Deleted flag) or delete from the database,
			# then disassociate this comment from the FB ID, and try to find any other comments with this FB ID
			while($cmt && (($cmt->top_commentid && $cmt->top_commentid->deleted) || !$cmt->top_commentid))
			{
				$cmt->external_id(0);
				$cmt->update;
				
				$cmt = Boards::Post->by_field(external_id => $fb_cmtid, deleted => 0);
			}
			
			if(!$cmt)
			{
				my $poster_fb_id = $cmt_ref->{from}->{id};
				my $poster_photo_url = "https://graph.facebook.com/" . $poster_fb_id . "/picture";
				
				# Attempt to locate a local user matching the Facebook user
				my $user = lookup_user($poster_fb_id, $cmt_ref->{from}->{name});
				$poster_photo_url = download_user_photo($user, $poster_photo_url, $poster_fb_id);
				
				my $has_top = $post->top_commentid && $post->top_commentid->id;
				my $data = {
					top_commentid		=> $has_top ? $post->top_commentid->id : $post->id,
					parent_commentid	=> $post->id, #$has_top ? 0 : $post->id, ## TODO Will this work or cauase problems to just set it to post->id regardless of $hash_top?
					poster_name		=> $cmt_ref->{from}->{name},
					poster_photo		=> $poster_photo_url,
					comment			=> $cmt_ref->{message},	
				};
				
				# Let Boards do the actual creation for us
				$cmt = $board_controller->create_new_comment($board,$post,$data,$user);
				
				# Revise the timestamp to match FB timestamp
				my $create_time = normalize_timestamp($cmt_ref->{created_time});
				$cmt->timestamp($create_time);
				
				# Flag it as from FB and store the FB Post ID for future reference
				$cmt->external_id($fb_cmtid);
				$cmt->external_source('Facebook');
				
				my ($user,$post_num,$cmt_num) = split /_/, $fb_cmtid;
				if($user && $post_num && $cmt_num)
				{
					$cmt->external_url('https://www.facebook.com/' . $user . '/posts/' . $post_num);
				}
				
				$cmt->data->set('fb_data', $cmt_ref);
				
				$cmt->update;
				
				my $url = AppCore::Config->get('WEBSITE_SERVER') . "/boards/".$cmt->top_commentid->boardid->folder_name."/".$cmt->top_commentid->folder_name."#c$cmt";
				print "Created comment# $cmt on post# '".$post->subject."' (top post: '".$cmt->top_commentid->subject."') - $url\n";
			}
			
			# Check for likes on this comment
			my $like_count = $cmt_ref->{count} || 0;
			if($like_count > 0)
			{
				my @count = Boards::Post::Like->search(postid => $cmt->id);
				if(@count != $like_count)
				{
					# Do a bit of funny math..
					my $diff = $like_count - @count;
					
					# Create anonymous likes
					Boards::Post::Like->insert({postid => $post}) for 0 .. $diff - 1;
					print "Comment: Created ($diff) anonymous likes on comment '".$cmt->subject."' - existing ".scalar(@count)." likes, total likes on FB $like_count\n" if $diff > 0;
				}
			}
		}
	}
}

sub download_user_photo
{
	my $user = shift;
	my $fb_poster_photo_url = shift;
	my $fb_id = shift;
	
	my $ident = $user ? join(':', AppCore::Config->get('WEBSITE_NAME'), $user->id) : $fb_id;
	
	my $local_photo_url = "/mods/User/user_photos/". ($user && $user->id ? "user". md5_hex($ident) : "fb".md5_hex($fb_id)).".jpg";
	my $file_path = AppCore::Config->get('APPCORE_ROOT') . $local_photo_url;
	
	my $poster_photo_url = AppCore::Config->get('WWW_ROOT') . $local_photo_url;

	my $mod_time = time - (stat($file_path))[9];
	#print STDERR "Modtime diff on $file_path: $mod_time\n";
	return $poster_photo_url if -f $file_path && ($mod_time) < 1 * 24 * 60 * 60 ; # just to speed it up...
	
	my $photo = LWP::Simple::get($fb_poster_photo_url);
	
	if(!open(PHOTO, '>' . $file_path))
	{
		print STDERR "Unable to write to $file_path: $!";
		return $poster_photo_url;
	}
	print PHOTO $photo;
	close(PHOTO);
	
	if($user && $user->id)
	{
		$user->photo(AppCore::Config->get('WWW_ROOT') . $local_photo_url);
		$user->update;
	}
	
	#print "Downloaded user photo to $file_path.\n";
	
	return $poster_photo_url;
}

sub normalize_timestamp
{
	my $time = shift;
	$time =~ s/^([^T]+)T([^\+\-]+)/$1 $2/g;
	my ($a,$b,$c,$d,$e,$f) = $time=~/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
	my $dt = DateTime->new(year=>$a,month=>$b,day=>$c,hour=>$d,minute=>$e,second=>$f,time_zone=>'UTC');
	$dt->subtract(hours=>4);
	return $dt->ymd('-').' '.$dt->hms(':');
}

__DATA__
# Data section exists for the purpose of locking

