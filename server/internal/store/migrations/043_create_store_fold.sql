-- store_fold makes store search tolerant of how Persian is typed (#243):
-- Arabic yeh, alef maksura, yeh with hamza, kaf, teh marbuta, heh with
-- yeh, the alef forms and waw with hamza become their Persian or plain
-- letters, ZWNJ becomes a space, the harakat, superscript alef and tatweel
-- go, and Latin letters are lower-cased. Queries are folded the same way.
CREATE OR REPLACE FUNCTION store_fold(input text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE RETURNS NULL ON NULL INPUT AS $$
    SELECT translate(lower(input),
        E'يىئكةۀأإآؤ‌'
            || E'ًٌٍَُِّْٰـ',
        E'یییکههاااو ')
$$;
