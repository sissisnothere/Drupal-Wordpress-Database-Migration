# Drupal 4 to wordpress 4.7 Miguration Script for SFA scholarship search site (www.sfa.ufl.edu/search)
#   The orginal script is  from http://www.hywel.me 
#   The following script has been modified and fits the needs to
#   Convert content types to costom post type
#   support custom-taxonomy
#   support custom field and custom filter


# Changelog
# 06.12.2016 - Updated by Hywel Llewellyn  http://www.hywel.me to support wordpress 4.5
# 07.29.2010 - Updated by Scott Anderson / Room 34 Creative Services http://blog.room34.com/archives/4530
# 02.06.2009 - Updated by Mike Smullin http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/
# 05.15.2007 - Updated by D’Arcy Norman http://www.darcynorman.net/2007/05/15/how-to-migrate-from-drupal-5-to-wordpress-2/
# 05.19.2006 - Created by Dave Dash http://spindrop.us/2006/05/19/migrating-from-drupal-47-to-wordpress/
# 11.02.2017 - updated by Xixi R to support Drupal 4 to wordpress 4.7 Miguration 


# This assumes that wordpress and Drupal are in separate databases, named 'wordpress' and 'search'.
# If your database names differ, adjust these accordingly.

# Empty previous content from wordpress database.
TRUNCATE TABLE wordpress.wp_comments;
TRUNCATE TABLE wordpress.wp_links;
TRUNCATE TABLE wordpress.wp_postmeta;
TRUNCATE TABLE wordpress.wp_posts;
TRUNCATE TABLE wordpress.wp_term_relationships;
TRUNCATE TABLE wordpress.wp_term_taxonomy;
TRUNCATE TABLE wordpress.wp_terms;


# insert college into term
# Using REPLACE prevents script from breaking if Drupal contains duplicate terms.
# REPLACE (str1, str2, str3)
# In str1, find where str2 occurs, and replace it with str3.
# REPLACE(txt, SUBSTRING(txt, LOCATE('(', txt), LENGTH(txt) - LOCATE(')', REVERSE(txt)) - LOCATE('(', txt) + 2), '')

REPLACE INTO wordpress.wp_terms
    (term_id, `name`, slug, term_group)
    SELECT DISTINCT 
       # d.tid, d.name, REPLACE(REPLACE(REPLACE(LOWER(d.name), ',', ' and'), '&', 'and'), ' ', '_'), 0
        d.tid, d.name, 
        REPLACE(
            REPLACE(
                REPLACE( # remove everything within ()
                    REPLACE(LOWER(d.name), SUBSTRING(LOWER(d.name), LOCATE('(', LOWER(d.name)), LENGTH(LOWER(d.name)) - LOCATE(')', REVERSE(LOWER(d.name))) - LOCATE('(', LOWER(d.name)) + 2), '')
                        , ',', ' and') #replace',' with 'and'
                , '&', 'and') #replace'&', with 'and'
            , ' ', '_') #replace ' ' with '_'
        , 0
    FROM search.d_term_data d
    INNER JOIN search.d_term_hierarchy h
        USING(tid)
    INNER JOIN search.d_term_node n
        USING(tid)
    WHERE (1
        # This helps eliminate spam tags from import; uncomment if necessary.
        # AND LENGTH(d.name) < 50
    )
;

# IMPORT college to Category
INSERT INTO wordpress.wp_term_taxonomy
    (term_id, taxonomy, description, parent)
    SELECT DISTINCT
        d.tid `term_id`,
        'category' `taxonomy`,
        d.description `description`,
        h.parent `parent`
    FROM search.d_term_data d
    INNER JOIN search.d_term_hierarchy h
        USING(tid)
    INNER JOIN search.d_term_node n
        USING(tid)
    WHERE (1
        # This helps eliminate spam tags from import; uncomment if necessary.
        # AND LENGTH(d.name) < 50
    )
;


# POSTS
# Keeps private posts hidden.
# • Related information in drupal ‘d_node’ (line 2036)
# • And ‘d_node_revisions’ l(ine 2161)
set session sql_mode = '';
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
    FROM search.d_node n
    INNER JOIN search.d_node_revisions r
        USING(vid)
    LEFT OUTER JOIN search.d_url_alias a
        ON a.src = CONCAT('node/', n.nid)
    # Add more Drupal content types below if applicable.
    WHERE n.type IN ('scholarship')
;


# POSTMETA 

# Custom Post Type
UPDATE wordpress.wp_posts
    SET post_type = 'post'
    WHERE post_type IN ('scholarship');


#insert DEGREES Type into Postmeta (custom field)
INSERT INTO wordpress.wp_postmeta
    (post_id, meta_value, meta_key)        
    SELECT 
        tt.sid `post_id`,
        tt.word `meta_value`,
        'field_degrees_value' `meta_key`  
        FROM search.d_search_index tt
        WHERE tt.type IN ('field_15')
;

#working
#9/21/2017
#insert DEGREES Type into term
#wp_terms (term_id, `name`, slug, term_group)
INSERT INTO wordpress.wp_terms(`name`, slug) VALUES ('Undergraduate', 'undergraduate');
INSERT INTO wordpress.wp_terms(`name`, slug) VALUES ('Graduate', 'graduate');
INSERT INTO wordpress.wp_terms (`name`, slug) VALUES ('Professional', 'professional');


#working
# IMPORT DEGREES to degree taxonomy
INSERT INTO wordpress.wp_term_taxonomy (term_id, taxonomy)
    SELECT 
        tt.term_id `term_id`,
        'degree' `taxonomy`
    FROM wordpress.wp_terms tt
    WHERE tt.slug = 'undergraduate' OR tt.slug = 'professional' OR tt.slug = 'graduate'
;

 

#insert REQUIRED CLASS STANDARD to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta
    (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_class_value `meta_value`,
        'field_class_value' `meta_key`  
        FROM search.d_content_field_class tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_field_class
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
     WHERE tt.field_class_value IS NOT NULL
;

#9/29/2017
# add majors to postmeta as custom field
UPDATE wordpress.wp_postmeta 
SET wordpress.wp_postmeta.meta_value = 
CASE
    WHEN wordpress.wp_postmeta.meta_value = 1 THEN REPLACE(wordpress.wp_postmeta.meta_value, '1', 'High School Senior')
    WHEN wordpress.wp_postmeta.meta_value = 2 THEN REPLACE(wordpress.wp_postmeta.meta_value, '2', 'College Freshman')
    WHEN wordpress.wp_postmeta.meta_value = 3 THEN REPLACE(wordpress.wp_postmeta.meta_value, '3', 'College Sophomore')
    WHEN wordpress.wp_postmeta.meta_value = 4 THEN REPLACE(wordpress.wp_postmeta.meta_value, '4', 'College Junior')
    WHEN wordpress.wp_postmeta.meta_value = 5 THEN REPLACE(wordpress.wp_postmeta.meta_value, '5', 'College Senior')
    WHEN wordpress.wp_postmeta.meta_value = 6 THEN REPLACE(wordpress.wp_postmeta.meta_value, '6', 'Graduate Student') 
END
WHERE wordpress.wp_postmeta.meta_key IN ('field_class_value')
;


#9/29/2017
#insert REQUIRED CLASS STANDARD  Type into term
INSERT INTO wordpress.wp_terms (`name`, slug)
    SELECT DISTINCT
        pm.meta_value `name`, 
        REPLACE(REPLACE(REPLACE(LOWER(pm.meta_value), ',', ' and'), '&', 'and'), ' ', '_') `slug`
    FROM wordpress.wp_postmeta AS pm
    WHERE pm.meta_key IN ('field_class_value')
;



#9/29
# IMPORT REQUIRED CLASS STANDARD  to degree taxonomy
INSERT INTO wordpress.wp_term_taxonomy (term_id, taxonomy)
    SELECT 
        tt.term_id `term_id`,
        'class' `taxonomy`
    FROM wordpress.wp_terms tt
    WHERE tt.slug = 'high_hchool_senior' OR tt.slug = 'college_freshman' OR tt.slug = 'college_sophomore'
            OR tt.slug = 'college_junior' OR tt.slug = 'college_senior' OR tt.slug = 'graduate_student'
;



#insert MAJORS to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta
    (post_id, meta_value, meta_key)        
     SELECT 
        tt.nid `post_id`,
        tt.field_fields_value `meta_value`,
        'field_majors_value' `meta_key`  
        FROM search.d_content_field_fields tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_field_fields
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
     WHERE tt.field_fields_value IS NOT NULL
;

# need to change database major name instand of number
UPDATE wordpress.wp_postmeta 
SET wordpress.wp_postmeta.meta_value = 
CASE
    WHEN wordpress.wp_postmeta.meta_value = 1 THEN REPLACE(wordpress.wp_postmeta.meta_value, '1', 'Accounting')
    WHEN wordpress.wp_postmeta.meta_value = 2 THEN REPLACE(wordpress.wp_postmeta.meta_value, '2', 'Advertising')
    WHEN wordpress.wp_postmeta.meta_value = 3 THEN REPLACE(wordpress.wp_postmeta.meta_value, '3', 'Aerospace Engineering')
    WHEN wordpress.wp_postmeta.meta_value = 4 THEN REPLACE(wordpress.wp_postmeta.meta_value, '4', 'Agricultural and Biological Engineering')
    WHEN wordpress.wp_postmeta.meta_value = 5 THEN REPLACE(wordpress.wp_postmeta.meta_value, '5', 'Agricultural Education and Communication')
    WHEN wordpress.wp_postmeta.meta_value = 6 THEN REPLACE(wordpress.wp_postmeta.meta_value, '6', 'Agricultural Operations Management') 
    WHEN wordpress.wp_postmeta.meta_value = 7 THEN REPLACE(wordpress.wp_postmeta.meta_value, '7', 'American Indian and Indigenous Studies') 
    WHEN wordpress.wp_postmeta.meta_value = 8 THEN REPLACE(wordpress.wp_postmeta.meta_value, '8', 'Animal Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 9 THEN REPLACE(wordpress.wp_postmeta.meta_value, '9', 'Anthropology')  
    WHEN wordpress.wp_postmeta.meta_value = 10 THEN REPLACE(wordpress.wp_postmeta.meta_value, '10', 'Applied Physiology and Kinesiology')  
    WHEN wordpress.wp_postmeta.meta_value = 11 THEN REPLACE(wordpress.wp_postmeta.meta_value, '11', 'Architecture')  
    WHEN wordpress.wp_postmeta.meta_value = 12 THEN REPLACE(wordpress.wp_postmeta.meta_value, '12', 'Art') 
    WHEN wordpress.wp_postmeta.meta_value = 13 THEN REPLACE(wordpress.wp_postmeta.meta_value, '13', 'Art Education')  
    WHEN wordpress.wp_postmeta.meta_value = 14 THEN REPLACE(wordpress.wp_postmeta.meta_value, '14', 'Art History') 
    WHEN wordpress.wp_postmeta.meta_value = 15 THEN REPLACE(wordpress.wp_postmeta.meta_value, '15', 'Astronomy')  
    WHEN wordpress.wp_postmeta.meta_value = 16 THEN REPLACE(wordpress.wp_postmeta.meta_value, '16', 'Athletic Training')  
    WHEN wordpress.wp_postmeta.meta_value = 17 THEN REPLACE(wordpress.wp_postmeta.meta_value, '17', 'Biochemistry') 
    WHEN wordpress.wp_postmeta.meta_value = 18 THEN REPLACE(wordpress.wp_postmeta.meta_value, '18', 'Athletic Training') 
    WHEN wordpress.wp_postmeta.meta_value = 19 THEN REPLACE(wordpress.wp_postmeta.meta_value, '19', 'Biochemistry and Molecular Biology (IDS)') 
    WHEN wordpress.wp_postmeta.meta_value = 20 THEN REPLACE(wordpress.wp_postmeta.meta_value, '20', 'Biology') 
    WHEN wordpress.wp_postmeta.meta_value = 21 THEN REPLACE(wordpress.wp_postmeta.meta_value, '21', 'Botany') 
    WHEN wordpress.wp_postmeta.meta_value = 22 THEN REPLACE(wordpress.wp_postmeta.meta_value, '22', 'Building Construction') 
    WHEN wordpress.wp_postmeta.meta_value = 23 THEN REPLACE(wordpress.wp_postmeta.meta_value, '23', 'Business Administration, General Business Online ') 
    WHEN wordpress.wp_postmeta.meta_value = 24 THEN REPLACE(wordpress.wp_postmeta.meta_value, '24', 'Business Administration, General Studies') 
    WHEN wordpress.wp_postmeta.meta_value = 25 THEN REPLACE(wordpress.wp_postmeta.meta_value, '25', 'Chemical Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 26 THEN REPLACE(wordpress.wp_postmeta.meta_value, '26', 'Chemistry') 
    WHEN wordpress.wp_postmeta.meta_value = 27 THEN REPLACE(wordpress.wp_postmeta.meta_value, '27', 'Civil Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 28 THEN REPLACE(wordpress.wp_postmeta.meta_value, '28', 'Classical Studies')
    WHEN wordpress.wp_postmeta.meta_value = 29 THEN REPLACE(wordpress.wp_postmeta.meta_value, '29', 'Computer Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 30 THEN REPLACE(wordpress.wp_postmeta.meta_value, '30', 'Computer Engineering')
    WHEN wordpress.wp_postmeta.meta_value = 31 THEN REPLACE(wordpress.wp_postmeta.meta_value, '31', 'Computer Science') 
    WHEN wordpress.wp_postmeta.meta_value = 32 THEN REPLACE(wordpress.wp_postmeta.meta_value, '32', 'Creative Photography') 
    WHEN wordpress.wp_postmeta.meta_value = 33 THEN REPLACE(wordpress.wp_postmeta.meta_value, '33', 'Criminology and Law') 
    WHEN wordpress.wp_postmeta.meta_value = 34 THEN REPLACE(wordpress.wp_postmeta.meta_value, '34', 'Dance') 
    WHEN wordpress.wp_postmeta.meta_value = 35 THEN REPLACE(wordpress.wp_postmeta.meta_value, '35', 'Decision and Information Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 36 THEN REPLACE(wordpress.wp_postmeta.meta_value, '36', 'Digital Arts and Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 37 THEN REPLACE(wordpress.wp_postmeta.meta_value, '37', 'East Asian Languages and Literatures') 
    WHEN wordpress.wp_postmeta.meta_value = 38 THEN REPLACE(wordpress.wp_postmeta.meta_value, '38', 'Economics') 
    WHEN wordpress.wp_postmeta.meta_value = 39 THEN REPLACE(wordpress.wp_postmeta.meta_value, '39', 'Education') 
    WHEN wordpress.wp_postmeta.meta_value = 40 THEN REPLACE(wordpress.wp_postmeta.meta_value, '40', 'Electrical Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 41 THEN REPLACE(wordpress.wp_postmeta.meta_value, '41', 'Engineering, Undecided')
    WHEN wordpress.wp_postmeta.meta_value = 42 THEN REPLACE(wordpress.wp_postmeta.meta_value, '42', 'English')
    WHEN wordpress.wp_postmeta.meta_value = 43 THEN REPLACE(wordpress.wp_postmeta.meta_value, '43', 'Entomology and Nematology')
    WHEN wordpress.wp_postmeta.meta_value = 44 THEN REPLACE(wordpress.wp_postmeta.meta_value, '44', 'Environmental Management in Agriculture and Natural Resources')
    WHEN wordpress.wp_postmeta.meta_value = 45 THEN REPLACE(wordpress.wp_postmeta.meta_value, '45', 'Environmental Science')
    WHEN wordpress.wp_postmeta.meta_value = 46 THEN REPLACE(wordpress.wp_postmeta.meta_value, '46', 'Environmental Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 47 THEN REPLACE(wordpress.wp_postmeta.meta_value, '47', 'Family, Youth and Community Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 48 THEN REPLACE(wordpress.wp_postmeta.meta_value, '48', 'Film and Media Studies (IDS)') 
    WHEN wordpress.wp_postmeta.meta_value = 49 THEN REPLACE(wordpress.wp_postmeta.meta_value, '49', 'Finance')  
    WHEN wordpress.wp_postmeta.meta_value = 50 THEN REPLACE(wordpress.wp_postmeta.meta_value, '50', 'Fire and Emergency Services')  
    WHEN wordpress.wp_postmeta.meta_value = 51 THEN REPLACE(wordpress.wp_postmeta.meta_value, '51', 'Food and Resource Economics')  
    WHEN wordpress.wp_postmeta.meta_value = 52 THEN REPLACE(wordpress.wp_postmeta.meta_value, '52', 'Food Science and Human Nutrition') 
    WHEN wordpress.wp_postmeta.meta_value = 53 THEN REPLACE(wordpress.wp_postmeta.meta_value, '53', 'Forest Resources and Conservation')  
    WHEN wordpress.wp_postmeta.meta_value = 54 THEN REPLACE(wordpress.wp_postmeta.meta_value, '54', 'French') 
    WHEN wordpress.wp_postmeta.meta_value = 55 THEN REPLACE(wordpress.wp_postmeta.meta_value, '55', 'Geography')  
    WHEN wordpress.wp_postmeta.meta_value = 56 THEN REPLACE(wordpress.wp_postmeta.meta_value, '56', 'Geology')  
    WHEN wordpress.wp_postmeta.meta_value = 57 THEN REPLACE(wordpress.wp_postmeta.meta_value, '57', 'Geomatics') 
    WHEN wordpress.wp_postmeta.meta_value = 58 THEN REPLACE(wordpress.wp_postmeta.meta_value, '58', 'German') 
    WHEN wordpress.wp_postmeta.meta_value = 59 THEN REPLACE(wordpress.wp_postmeta.meta_value, '59', 'Gold and Sports Turf Management (IDS)') 
    WHEN wordpress.wp_postmeta.meta_value = 60 THEN REPLACE(wordpress.wp_postmeta.meta_value, '60', 'Graphic Design') 
    WHEN wordpress.wp_postmeta.meta_value = 61 THEN REPLACE(wordpress.wp_postmeta.meta_value, '61', 'Health Education and Behavior') 
    WHEN wordpress.wp_postmeta.meta_value = 62 THEN REPLACE(wordpress.wp_postmeta.meta_value, '62', 'Health Science') 
    WHEN wordpress.wp_postmeta.meta_value = 63 THEN REPLACE(wordpress.wp_postmeta.meta_value, '63', 'History') 
    WHEN wordpress.wp_postmeta.meta_value = 64 THEN REPLACE(wordpress.wp_postmeta.meta_value, '64', 'Horticultural Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 65 THEN REPLACE(wordpress.wp_postmeta.meta_value, '65', 'Industrial and Systems Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 66 THEN REPLACE(wordpress.wp_postmeta.meta_value, '66', 'Information Systems') 
    WHEN wordpress.wp_postmeta.meta_value = 67 THEN REPLACE(wordpress.wp_postmeta.meta_value, '67', 'Interior Design') 
    WHEN wordpress.wp_postmeta.meta_value = 68 THEN REPLACE(wordpress.wp_postmeta.meta_value, '68', 'International Studies')
    WHEN wordpress.wp_postmeta.meta_value = 69 THEN REPLACE(wordpress.wp_postmeta.meta_value, '69', 'Jewish Studies') 
    WHEN wordpress.wp_postmeta.meta_value = 70 THEN REPLACE(wordpress.wp_postmeta.meta_value, '70', 'Journalism')
    WHEN wordpress.wp_postmeta.meta_value = 71 THEN REPLACE(wordpress.wp_postmeta.meta_value, '71', 'Landscape and Nursery Horticulture') 
    WHEN wordpress.wp_postmeta.meta_value = 72 THEN REPLACE(wordpress.wp_postmeta.meta_value, '72', 'Landscape Architecture') 
    WHEN wordpress.wp_postmeta.meta_value = 73 THEN REPLACE(wordpress.wp_postmeta.meta_value, '73', 'Linguistics') 
    WHEN wordpress.wp_postmeta.meta_value = 74 THEN REPLACE(wordpress.wp_postmeta.meta_value, '74', 'Management') 
    WHEN wordpress.wp_postmeta.meta_value = 75 THEN REPLACE(wordpress.wp_postmeta.meta_value, '75', 'Marketing') 
    WHEN wordpress.wp_postmeta.meta_value = 76 THEN REPLACE(wordpress.wp_postmeta.meta_value, '76', 'Materials Science and Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 77 THEN REPLACE(wordpress.wp_postmeta.meta_value, '77', 'Mathematics') 
    WHEN wordpress.wp_postmeta.meta_value = 78 THEN REPLACE(wordpress.wp_postmeta.meta_value, '78', 'Mechanical Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 79 THEN REPLACE(wordpress.wp_postmeta.meta_value, '79', 'Medieval and Early Modern Studies (IDS)') 
    WHEN wordpress.wp_postmeta.meta_value = 80 THEN REPLACE(wordpress.wp_postmeta.meta_value, '80', 'Microbiology and Cell Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 81 THEN REPLACE(wordpress.wp_postmeta.meta_value, '81', 'Middle Eastern Languages and Cultures (IDS)')
    WHEN wordpress.wp_postmeta.meta_value = 82 THEN REPLACE(wordpress.wp_postmeta.meta_value, '82', 'Modern European Studies (IDS)')
    WHEN wordpress.wp_postmeta.meta_value = 83 THEN REPLACE(wordpress.wp_postmeta.meta_value, '83', 'Music')
    WHEN wordpress.wp_postmeta.meta_value = 84 THEN REPLACE(wordpress.wp_postmeta.meta_value, '84', 'Music Education')
    WHEN wordpress.wp_postmeta.meta_value = 85 THEN REPLACE(wordpress.wp_postmeta.meta_value, '85', 'Natural Resource Conservation')
    WHEN wordpress.wp_postmeta.meta_value = 86 THEN REPLACE(wordpress.wp_postmeta.meta_value, '86', 'Neurobiological Sciences (IDS)') 
    WHEN wordpress.wp_postmeta.meta_value = 87 THEN REPLACE(wordpress.wp_postmeta.meta_value, '87', 'Nuclear and Radiological Sciences') 
    WHEN wordpress.wp_postmeta.meta_value = 88 THEN REPLACE(wordpress.wp_postmeta.meta_value, '88', 'Nuclear Engineering') 
    WHEN wordpress.wp_postmeta.meta_value = 89 THEN REPLACE(wordpress.wp_postmeta.meta_value, '89', 'Nursing')  
    WHEN wordpress.wp_postmeta.meta_value = 90 THEN REPLACE(wordpress.wp_postmeta.meta_value, '90', 'Packaging Science')  
    WHEN wordpress.wp_postmeta.meta_value = 91 THEN REPLACE(wordpress.wp_postmeta.meta_value, '91', 'Pharmacy')  
    WHEN wordpress.wp_postmeta.meta_value = 92 THEN REPLACE(wordpress.wp_postmeta.meta_value, '92', 'Philosophy') 
    WHEN wordpress.wp_postmeta.meta_value = 93 THEN REPLACE(wordpress.wp_postmeta.meta_value, '93', 'Physics')  
    WHEN wordpress.wp_postmeta.meta_value = 94 THEN REPLACE(wordpress.wp_postmeta.meta_value, '94', 'Plant Science') 
    WHEN wordpress.wp_postmeta.meta_value = 95 THEN REPLACE(wordpress.wp_postmeta.meta_value, '95', 'Political Science')  
    WHEN wordpress.wp_postmeta.meta_value = 96 THEN REPLACE(wordpress.wp_postmeta.meta_value, '96', 'Portuguese')  
    WHEN wordpress.wp_postmeta.meta_value = 97 THEN REPLACE(wordpress.wp_postmeta.meta_value, '97', 'Psychology') 
    WHEN wordpress.wp_postmeta.meta_value = 98 THEN REPLACE(wordpress.wp_postmeta.meta_value, '98', 'Public Relations') 
    WHEN wordpress.wp_postmeta.meta_value = 99 THEN REPLACE(wordpress.wp_postmeta.meta_value, '99', 'Recreation, Parks and Tourism') 
    WHEN wordpress.wp_postmeta.meta_value = 100 THEN REPLACE(wordpress.wp_postmeta.meta_value, '100', 'Religion') 
    WHEN wordpress.wp_postmeta.meta_value = 101 THEN REPLACE(wordpress.wp_postmeta.meta_value, '101', 'Russian') 
    WHEN wordpress.wp_postmeta.meta_value = 102 THEN REPLACE(wordpress.wp_postmeta.meta_value, '102', 'Sociology') 
    WHEN wordpress.wp_postmeta.meta_value = 103 THEN REPLACE(wordpress.wp_postmeta.meta_value, '103', 'Soil and Water Science') 
    WHEN wordpress.wp_postmeta.meta_value = 104 THEN REPLACE(wordpress.wp_postmeta.meta_value, '104', 'Spanish') 
    WHEN wordpress.wp_postmeta.meta_value = 105 THEN REPLACE(wordpress.wp_postmeta.meta_value, '105', 'Sport Management') 
    WHEN wordpress.wp_postmeta.meta_value = 106 THEN REPLACE(wordpress.wp_postmeta.meta_value, '106', 'Statistics') 
    WHEN wordpress.wp_postmeta.meta_value = 107 THEN REPLACE(wordpress.wp_postmeta.meta_value, '107', 'Sustainability and the Built Environment') 
    WHEN wordpress.wp_postmeta.meta_value = 108 THEN REPLACE(wordpress.wp_postmeta.meta_value, '108', 'Classical Studies')
    WHEN wordpress.wp_postmeta.meta_value = 109 THEN REPLACE(wordpress.wp_postmeta.meta_value, '109', 'Theatre Performance') 
    WHEN wordpress.wp_postmeta.meta_value = 110 THEN REPLACE(wordpress.wp_postmeta.meta_value, '110', 'Theatre, General')
    WHEN wordpress.wp_postmeta.meta_value = 111 THEN REPLACE(wordpress.wp_postmeta.meta_value, '111', 'Visual Art Studies') 
    WHEN wordpress.wp_postmeta.meta_value = 112 THEN REPLACE(wordpress.wp_postmeta.meta_value, '112', 'Wildlife Ecology and Conservation') 
    WHEN wordpress.wp_postmeta.meta_value = 113 THEN REPLACE(wordpress.wp_postmeta.meta_value, '113', 'Women Studies') 
    WHEN wordpress.wp_postmeta.meta_value = 114 THEN REPLACE(wordpress.wp_postmeta.meta_value, '114', 'Zoology') 
    ELSE REPLACE(wordpress.wp_postmeta.meta_value, '', 'Others') 
END
WHERE wordpress.wp_postmeta.meta_key IN ('field_majors_value')
;

#9/29/2017
#insert Major Type into term
#wp_terms (term_id, `name`, slug, term_group)
INSERT INTO wordpress.wp_terms (`name`, slug)
    SELECT DISTINCT
        pm.meta_value `name`, 
        REPLACE(REPLACE(REPLACE(LOWER(pm.meta_value), ',', ' and'), '&', 'and'), ' ', '_') `slug`
    FROM wordpress.wp_postmeta AS pm
    WHERE pm.meta_key IN ('field_majors_value')
;


#9/29
# IMPORT MAJOR to degree taxonomy
INSERT INTO wordpress.wp_term_taxonomy (term_id, taxonomy)
    SELECT DISTINCT
        tt.term_id `term_id`,
        'major' `taxonomy`
    FROM wordpress.wp_terms AS tt, wordpress.wp_postmeta AS pm
    WHERE (tt.name = pm.meta_value) AND (pm.meta_key IN ('field_majors_value'))
;


#9/29/2017
#update  ???(can be all ??? not only the degree!) term_relationship using wp_postmeta and wp_terms and wp_term_taxonomy tables
INSERT INTO wordpress.wp_term_relationships (object_id, term_taxonomy_id)
    SELECT  pm.post_id `object_id`,
            temp.term_taxonomy_id `term_taxonomy_id`
    FROM wordpress.wp_postmeta AS pm
    INNER JOIN (
        SELECT term.name, ta.term_taxonomy_id
        FROM  wordpress.wp_term_taxonomy AS ta
        INNER JOIN wordpress.wp_terms AS term
        ON term.term_id =  ta.term_id
    ) AS temp ON pm.meta_value = temp.name
; 


# POST/TAG RELATIONSHIPS
INSERT INTO wordpress.wp_term_relationships (object_id, term_taxonomy_id)
    SELECT DISTINCT nid, tid FROM search.d_term_node
;

####### belows are the postmeta (custom filed) ##############


#insert NEEDBASED SCHOLARSHIP to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta
    (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_need_value `meta_value`,
        'field_need_value' `meta_key`  
        FROM search.d_content_type_scholarship tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_type_scholarship
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
;

#insert UF SCHOLARSHIP to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_uf_value `meta_value`,
        'field_uf_value' `meta_key`  
        FROM search.d_content_type_scholarship tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_type_scholarship
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
;

#insert GPA  to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_gpa_value `meta_value`,
        'field_gpa_value' `meta_key`  
        FROM search.d_content_type_scholarship tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_type_scholarship
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
        WHERE tt.field_gpa_value IS NOT NULL
;


#insert DEADLINE to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_deadline_value `meta_value`,
        'field_deadline_value' `meta_key`  
        FROM search.d_content_type_scholarship tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_type_scholarship
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
     WHERE tt.field_deadline_value IS NOT NULL
;

#reformate deadliine value
UPDATE wordpress.wp_postmeta 
SET wordpress.wp_postmeta.meta_value = REPLACE( wordpress.wp_postmeta.meta_value, wordpress.wp_postmeta.meta_value, SUBSTRING(wordpress.wp_postmeta.meta_value, 1, 10)) 
WHERE wordpress.wp_postmeta.meta_key IN ('field_deadline_value')
;


#insert VALUE to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_value_value `meta_value`,
        'field_value_value' `meta_key`  
        FROM search.d_content_type_scholarship tt
        INNER JOIN  
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_type_scholarship
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
     WHERE tt.field_value_value IS NOT NULL
;

#insert EXPIRE to wp_postmeta as a custom field
INSERT INTO wordpress.wp_postmeta (post_id, meta_value, meta_key)        
    SELECT 
        tt.nid `post_id`,
        tt.field_expire_value `meta_value`,
        'field_expire_value' `meta_key`  
        FROM search.d_content_type_scholarship tt
        INNER JOIN
            (
            SELECT nid, MAX(vid) AS MaxVID
            FROM search.d_content_type_scholarship
            GROUP BY nid
            ) groupedtt ON tt.nid = groupedtt .nid AND tt.vid = groupedtt.MaxVID
    WHERE  tt.field_expire_value IS NOT NULL
;


# delete rows in the postmeta field with field_majors_value, field_class_value, field_degrees_value
# because they are already in the categories not need to be in the postmeta
# 9/29/2017
DELETE FROM wordpress.wp_postmeta
WHERE meta_key = 'field_majors_value' OR  meta_key = 'field_class_value' OR meta_key = 'field_degrees_value'
;

#9/29/2017
# Update (all) category counts.
SET SQL_SAFE_UPDATES=0;
UPDATE wordpress.wp_term_taxonomy tt
    SET `count` = (
        SELECT COUNT(tr.object_id)
        FROM wordpress.wp_term_relationships tr
        WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
    )
;


# Fix taxonomy; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-27140
#11/3/2017 
#fixed college sholarship error

UPDATE IGNORE wordpress.wp_term_relationships tr
    SET tr.term_taxonomy_id = (
        SELECT tt.term_taxonomy_id
        FROM wordpress.wp_term_taxonomy tt
        WHERE tr.term_taxonomy_id = tt.term_id
    ) 
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
# wordpress URLs. If you have mod_rewrite turned on, stripping out the portion before
# the final slash will allow old site links to work properly, even if the path before
# the slash is different!
UPDATE wordpress.wp_posts
    SET post_name =
    REVERSE(SUBSTRING(REVERSE(post_name),1,LOCATE('/',REVERSE(post_name))-1))
;

SET SQL_SAFE_UPDATES=1;
# convert all tags to categories
# UPDATE wp_term_taxonomy SET taxonomy='category' WHERE taxonomy='post_tag'