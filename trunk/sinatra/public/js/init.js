jQuery.prototype.highlight = function() {
  jQuery(this).css("background-color","yellow").fadeTo('slow', 0.1, function() {
    jQuery(this).fadeTo('slow', 1.0, function() {
        jQuery(this).css("background-color","yellow").fadeTo('slow', 0, function() {});
    });
  });
};

$(function() {
	//jQuery('#flash').highlight();
});
