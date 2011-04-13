$(document).ready(function() {
	windowsize = window.innerWidth; //Get browser size for slide overs
	setTimeout(scrollTo, 0, 0, 1); //Hide nav bar in mobile safari

	var currentBlock = 0;   //js pointer
	var transTime    = 400; //milliseconds
	var blockHeight  = 322; //pixels
	var lastLink     = 0;   //js pointer
	function showBlock(blockSuffix)
	{
		var newBlockId = 'block-'+blockSuffix;
		var newLinkId  = 'link-' +blockSuffix
		
		if(currentBlock)
		{
			// animate the hiding of the currently visible block
			currentBlock.animate({top: '-' + blockHeight}, transTime,
				function() {
					// after anim, put the block back down below the viewport
					$(this).animate({top:blockHeight},0);
				}
			);
		}
		
		// animate the requested block
		currentBlock = $('#'+newBlockId);
		currentBlock.animate({top:0}, transTime);
		
		// update link styles
		if(lastLink)
			lastLink.removeClass('current');
		
		var linkElm = $('#'+newLinkId);
		if(linkElm)
		{
			linkElm.addClass('current');
			lastLink = linkElm;
		}
	}
	
	// list of block suffixes to rotate through
	var blockList     = ['title-slide','video','events','photos','prayers'];
	var blockIdx      = -1;     // current index into blockList 
	var blockShowTime = 5000;   // length of time to show each block
	var userOverride  = false;  // if true, dont auto change blocks
	function showNextBlock()
	{
		if(userOverride)
			return;
		
		// get next block#
		blockIdx ++;
		if(blockIdx >= blockList.length)
			blockIdx = 0;
			
		// show the block
		var blockSuffix = blockList[blockIdx];
		showBlock(blockSuffix);
		
		// set timer to change blocks
		setTimeout(showNextBlock, blockShowTime);
	}
	
	
	// start the rotator
	setTimeout(showNextBlock, 100);
	
	$('#sidebar .sidebar-link-block .link-block').live("click", function() {
	
		var suffix = $(this).attr('block-suffix');
		if(!suffix)
		{
			suffix = $(this).attr('href');
			suffix = suffix.substr(1,suffix.length());
		}
		
		showBlock(suffix);
		
		userOverride = true;
		
		return false;
	});
	
	$("#header .logo a").live("click", function() { // Main Navigation
		var url = $(this).attr('href');
		$(this).ajaxSend(function() {
			$('#loading-box').show();
		});
		$(this).ajaxSuccess(function() {
			$('#loading-box').hide();
			$(this).unbind("ajaxSend");
		});
		$('#site-container').load(url);
		return false;
	});
	
	$("#nav ul li a").live("click", function() { // Main Navigation
		var url = $(this).attr('href');
		$(this).ajaxSend(function() {
			$('#loading-box').show();
		});
		$(this).ajaxSuccess(function() {
			$('#loading-box').hide();
			$(this).unbind("ajaxSend");
		});
		$('#site-container').load(url);
		return false;
	});
	
	$('.content .other-link').live("click", function() { // Ajax link to contact forms
		var url = $(this).attr('href');
		$('#selected-item .content').load(url, function() {
			$('#selected-item').show();
			$.scrollTo(0,0);
			$('#main-page').animate({left: '-'+windowsize},400);
		});
		return false;
	});	
});