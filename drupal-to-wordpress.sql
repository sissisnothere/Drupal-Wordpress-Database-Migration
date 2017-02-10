# Drupal 4 to Wordpress 4.7 Miguration Script for SFA scholarship search site (www.sfa.ufl.edu/search)
# 	The orginal script is  from http://www.hywel.me 
# 	The following script has been modified and fits the needs to
#	Convert content types to costom post type
#   support custom-taxonomy
#	support custom field and custom filter


# Changelog
# 02.07.2017 - updated by Xixi R to support Drupal 4 to Wordpress 4.7 Miguration 


# This assumes that WordPress and Drupal are in separate databases, named 'wordpress' and 'drupal_wp'.
# If your database names differ, adjust these accordingly.

# Empty previous content from WordPress database.
TRUNCATE TABLE wordpress.wp_comments;
TRUNCATE TABLE wordpress.wp_links;
TRUNCATE TABLE wordpress.wp_postmeta;
TRUNCATE TABLE wordpress.wp_posts;
TRUNCATE TABLE wordpress.wp_term_relationships;
TRUNCATE TABLE wordpress.wp_term_taxonomy;
TRUNCATE TABLE wordpress.wp_terms;


# TAGS 
# Using REPLACE prevents script from breaking if Drupal contains duplicate terms.
REPLACE INTO wordpress.wp_terms
	(term_id, `name`, slug, term_group)
	SELECT DISTINCT
		d.tid, d.name, REPLACE(LOWER(d.name), ' ', '_'), 0
	FROM drupal_wp.d_term_data d
	INNER JOIN drupal_wp.d_term_hierarchy h
		USING(tid)
	INNER JOIN drupal_wp.d_term_node n
		USING(tid)
	WHERE (1
	 	# This helps eliminate spam tags from import; uncomment if necessary.
	 	# AND LENGTH(d.name) < 50
	)
;
# TODO: Import Custom Taxonomy
INSERT INTO wordpress.wp_term_taxonomy
	(term_id, taxonomy, description, parent)
	SELECT DISTINCT
		d.tid `term_id`,
		'post_tag' `taxonomy`,
		d.description `description`,
		h.parent `parent`
	FROM drupal_wp.d_term_data d
	INNER JOIN drupal_wp.d_term_hierarchy h
		USING(tid)
	INNER JOIN drupal_wp.d_term_node n
		USING(tid)
	WHERE (1
	 	# This helps eliminate spam tags from import; uncomment if necessary.
	 	# AND LENGTH(d.name) < 50
	)
;

# POSTS
# Keeps private posts hidden.
# •	Related information in drupal ‘d_node’ (line 2036)
# •	And ‘d_node_revisions’ l(ine 2161)

INSERT INTO wordpress.wp_posts
	(id, post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_modified, post_type, `post_status`)
	SELECT DISTINCT
		n.nid `id`,
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		r.body `post_content`,
		n.title `post_title`,
		r.teaser `post_excerpt`,
		IF(SUBSTR(a.dst, 11, 1) = '/', SUBSTR(a.dst, 12), a.dst) `post_name`,
		FROM_UNIXTIME(n.changed) `post_modified`,
		n.type `post_type`,
		IF(n.status = 1, 'publish', 'private') `post_status`
	FROM drupal_wp.d_node n
	INNER JOIN drupal_wp.d_node_revisions r
		USING(vid)
	LEFT OUTER JOIN drupal_wp.d_url_alias a
		ON a.src = CONCAT('node/', n.nid)
	# Add more Drupal content types below if applicable.
	WHERE n.type IN ('scholarship')
;

# Update category counts.
UPDATE wordpress.wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wordpress.wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# Custom Post Type
UPDATE wordpress.wp_posts
	SET post_type = 'scholarship-post'
	WHERE post_type IN ('scholarship');

# POST/TAG RELATIONSHIPS
INSERT INTO wordpress.wp_term_relationships (object_id, term_taxonomy_id)
	SELECT DISTINCT nid, tid FROM drupal_wp.d_term_node
;

# Update tag counts.
UPDATE wordpress.wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wordpress.wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# Fix taxonomy; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-27140
UPDATE IGNORE wordpress.wp_term_relationships, wordpress.wp_term_taxonomy
	SET wordpress.wp_term_relationships.term_taxonomy_id = wordpress.wp_term_taxonomy.term_taxonomy_id
	WHERE wordpress.wp_term_relationships.term_taxonomy_id = wordpress.wp_term_taxonomy.term_id
;

# OPTIONAL ADDITIONS -- REMOVE ALL BELOW IF NOT APPLICABLE TO YOUR CONFIGURATION



# Miscellaneous clean-up.
# There may be some extraneous blank spaces in your Drupal posts; use these queries
# or other similar ones to strip out the undesirable tags.
UPDATE wordpress.wp_posts
	SET post_content = REPLACE(post_content,'<p>&nbsp;</p>','')
;
UPDATE wordpress.wp_posts
	SET post_content = REPLACE(post_content,'<p class="italic">&nbsp;</p>','')
;


# Fix post_name to remove paths.
# If applicable; Drupal allows paths (i.e. slashes) in the dst field, but this breaks
# WordPress URLs. If you have mod_rewrite turned on, stripping out the portion before
# the final slash will allow old site links to work properly, even if the path before
# the slash is different!
UPDATE wordpress.wp_posts
	SET post_name =
	REVERSE(SUBSTRING(REVERSE(post_name),1,LOCATE('/',REVERSE(post_name))-1))
;