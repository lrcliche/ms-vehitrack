-- =====================================================================================
-- VehiTrack · seeds/municipality_co.sql
-- Catalogo nacional de municipios de Colombia (Divipola DANE).
--
-- NO es una migracion: es data. Se aplica DESPUES de 001-004, como dueno:
--   psql "$POSTGRES_DSN" -f seeds/municipality_co.sql
--
-- Fuente: DANE — Divipola (datos.gov.co, recurso gdxc-w37w). 33 divisiones (32 dptos +
-- Bogota D.C.). 1104 filas = 1103 tipo 'Municipio' + San Andres (el DANE lo tipa 'Isla',
-- pero es la capital del archipielago y se navega, asi que se incluye). Se EXCLUYEN las
-- 18 areas no municipalizadas de Amazonia/Orinoquia: no son municipios.
--
-- id = co-<iso>-<slug> (iso = ISO 3166-2:CO en minuscula). department_id = co-<iso> (text
-- libre, sin FK). geom NULL: la carga import_municipality_geom.(ps1|sh). Idempotente:
-- ON CONFLICT (id) DO NOTHING. SET client_encoding hace la carga a prueba de consola cp1252.
-- =====================================================================================

BEGIN;
SET client_encoding TO 'UTF8';

-- ANT · Antioquia (DANE 05) — 125 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-ant-medellin',                   'co-ant', 'Medellín'),  -- DANE 05001
  ('co-ant-abejorral',                  'co-ant', 'Abejorral'),  -- DANE 05002
  ('co-ant-abriaqui',                   'co-ant', 'Abriaquí'),  -- DANE 05004
  ('co-ant-alejandria',                 'co-ant', 'Alejandría'),  -- DANE 05021
  ('co-ant-amaga',                      'co-ant', 'Amagá'),  -- DANE 05030
  ('co-ant-amalfi',                     'co-ant', 'Amalfi'),  -- DANE 05031
  ('co-ant-andes',                      'co-ant', 'Andes'),  -- DANE 05034
  ('co-ant-angelopolis',                'co-ant', 'Angelópolis'),  -- DANE 05036
  ('co-ant-angostura',                  'co-ant', 'Angostura'),  -- DANE 05038
  ('co-ant-anori',                      'co-ant', 'Anorí'),  -- DANE 05040
  ('co-ant-santa-fe-de-antioquia',      'co-ant', 'Santa Fé de Antioquia'),  -- DANE 05042
  ('co-ant-anza',                       'co-ant', 'Anzá'),  -- DANE 05044
  ('co-ant-apartado',                   'co-ant', 'Apartadó'),  -- DANE 05045
  ('co-ant-arboletes',                  'co-ant', 'Arboletes'),  -- DANE 05051
  ('co-ant-argelia',                    'co-ant', 'Argelia'),  -- DANE 05055
  ('co-ant-armenia',                    'co-ant', 'Armenia'),  -- DANE 05059
  ('co-ant-barbosa',                    'co-ant', 'Barbosa'),  -- DANE 05079
  ('co-ant-belmira',                    'co-ant', 'Belmira'),  -- DANE 05086
  ('co-ant-bello',                      'co-ant', 'Bello'),  -- DANE 05088
  ('co-ant-betania',                    'co-ant', 'Betania'),  -- DANE 05091
  ('co-ant-betulia',                    'co-ant', 'Betulia'),  -- DANE 05093
  ('co-ant-ciudad-bolivar',             'co-ant', 'Ciudad Bolívar'),  -- DANE 05101
  ('co-ant-briceno',                    'co-ant', 'Briceño'),  -- DANE 05107
  ('co-ant-buritica',                   'co-ant', 'Buriticá'),  -- DANE 05113
  ('co-ant-caceres',                    'co-ant', 'Cáceres'),  -- DANE 05120
  ('co-ant-caicedo',                    'co-ant', 'Caicedo'),  -- DANE 05125
  ('co-ant-caldas',                     'co-ant', 'Caldas'),  -- DANE 05129
  ('co-ant-campamento',                 'co-ant', 'Campamento'),  -- DANE 05134
  ('co-ant-canasgordas',                'co-ant', 'Cañasgordas'),  -- DANE 05138
  ('co-ant-caracoli',                   'co-ant', 'Caracolí'),  -- DANE 05142
  ('co-ant-caramanta',                  'co-ant', 'Caramanta'),  -- DANE 05145
  ('co-ant-carepa',                     'co-ant', 'Carepa'),  -- DANE 05147
  ('co-ant-el-carmen-de-viboral',       'co-ant', 'El Carmen de Viboral'),  -- DANE 05148
  ('co-ant-carolina',                   'co-ant', 'Carolina'),  -- DANE 05150
  ('co-ant-caucasia',                   'co-ant', 'Caucasia'),  -- DANE 05154
  ('co-ant-chigorodo',                  'co-ant', 'Chigorodó'),  -- DANE 05172
  ('co-ant-cisneros',                   'co-ant', 'Cisneros'),  -- DANE 05190
  ('co-ant-cocorna',                    'co-ant', 'Cocorná'),  -- DANE 05197
  ('co-ant-concepcion',                 'co-ant', 'Concepción'),  -- DANE 05206
  ('co-ant-concordia',                  'co-ant', 'Concordia'),  -- DANE 05209
  ('co-ant-copacabana',                 'co-ant', 'Copacabana'),  -- DANE 05212
  ('co-ant-dabeiba',                    'co-ant', 'Dabeiba'),  -- DANE 05234
  ('co-ant-donmatias',                  'co-ant', 'Donmatías'),  -- DANE 05237
  ('co-ant-ebejico',                    'co-ant', 'Ebéjico'),  -- DANE 05240
  ('co-ant-el-bagre',                   'co-ant', 'El Bagre'),  -- DANE 05250
  ('co-ant-entrerrios',                 'co-ant', 'Entrerríos'),  -- DANE 05264
  ('co-ant-envigado',                   'co-ant', 'Envigado'),  -- DANE 05266
  ('co-ant-fredonia',                   'co-ant', 'Fredonia'),  -- DANE 05282
  ('co-ant-frontino',                   'co-ant', 'Frontino'),  -- DANE 05284
  ('co-ant-giraldo',                    'co-ant', 'Giraldo'),  -- DANE 05306
  ('co-ant-girardota',                  'co-ant', 'Girardota'),  -- DANE 05308
  ('co-ant-gomez-plata',                'co-ant', 'Gómez Plata'),  -- DANE 05310
  ('co-ant-granada',                    'co-ant', 'Granada'),  -- DANE 05313
  ('co-ant-guadalupe',                  'co-ant', 'Guadalupe'),  -- DANE 05315
  ('co-ant-guarne',                     'co-ant', 'Guarne'),  -- DANE 05318
  ('co-ant-guatape',                    'co-ant', 'Guatapé'),  -- DANE 05321
  ('co-ant-heliconia',                  'co-ant', 'Heliconia'),  -- DANE 05347
  ('co-ant-hispania',                   'co-ant', 'Hispania'),  -- DANE 05353
  ('co-ant-itagui',                     'co-ant', 'Itagüí'),  -- DANE 05360
  ('co-ant-ituango',                    'co-ant', 'Ituango'),  -- DANE 05361
  ('co-ant-jardin',                     'co-ant', 'Jardín'),  -- DANE 05364
  ('co-ant-jerico',                     'co-ant', 'Jericó'),  -- DANE 05368
  ('co-ant-la-ceja',                    'co-ant', 'La Ceja'),  -- DANE 05376
  ('co-ant-la-estrella',                'co-ant', 'La Estrella'),  -- DANE 05380
  ('co-ant-la-pintada',                 'co-ant', 'La Pintada'),  -- DANE 05390
  ('co-ant-la-union',                   'co-ant', 'La Unión'),  -- DANE 05400
  ('co-ant-liborina',                   'co-ant', 'Liborina'),  -- DANE 05411
  ('co-ant-maceo',                      'co-ant', 'Maceo'),  -- DANE 05425
  ('co-ant-marinilla',                  'co-ant', 'Marinilla'),  -- DANE 05440
  ('co-ant-montebello',                 'co-ant', 'Montebello'),  -- DANE 05467
  ('co-ant-murindo',                    'co-ant', 'Murindó'),  -- DANE 05475
  ('co-ant-mutata',                     'co-ant', 'Mutatá'),  -- DANE 05480
  ('co-ant-narino',                     'co-ant', 'Nariño'),  -- DANE 05483
  ('co-ant-necocli',                    'co-ant', 'Necoclí'),  -- DANE 05490
  ('co-ant-nechi',                      'co-ant', 'Nechí'),  -- DANE 05495
  ('co-ant-olaya',                      'co-ant', 'Olaya'),  -- DANE 05501
  ('co-ant-penol',                      'co-ant', 'Peñol'),  -- DANE 05541
  ('co-ant-peque',                      'co-ant', 'Peque'),  -- DANE 05543
  ('co-ant-pueblorrico',                'co-ant', 'Pueblorrico'),  -- DANE 05576
  ('co-ant-puerto-berrio',              'co-ant', 'Puerto Berrío'),  -- DANE 05579
  ('co-ant-puerto-nare',                'co-ant', 'Puerto Nare'),  -- DANE 05585
  ('co-ant-puerto-triunfo',             'co-ant', 'Puerto Triunfo'),  -- DANE 05591
  ('co-ant-remedios',                   'co-ant', 'Remedios'),  -- DANE 05604
  ('co-ant-retiro',                     'co-ant', 'Retiro'),  -- DANE 05607
  ('co-ant-rionegro',                   'co-ant', 'Rionegro'),  -- DANE 05615
  ('co-ant-sabanalarga',                'co-ant', 'Sabanalarga'),  -- DANE 05628
  ('co-ant-sabaneta',                   'co-ant', 'Sabaneta'),  -- DANE 05631
  ('co-ant-salgar',                     'co-ant', 'Salgar'),  -- DANE 05642
  ('co-ant-san-andres-de-cuerquia',     'co-ant', 'San Andrés de Cuerquía'),  -- DANE 05647
  ('co-ant-san-carlos',                 'co-ant', 'San Carlos'),  -- DANE 05649
  ('co-ant-san-francisco',              'co-ant', 'San Francisco'),  -- DANE 05652
  ('co-ant-san-jeronimo',               'co-ant', 'San Jerónimo'),  -- DANE 05656
  ('co-ant-san-jose-de-la-montana',     'co-ant', 'San José de la Montaña'),  -- DANE 05658
  ('co-ant-san-juan-de-uraba',          'co-ant', 'San Juan de Urabá'),  -- DANE 05659
  ('co-ant-san-luis',                   'co-ant', 'San Luis'),  -- DANE 05660
  ('co-ant-san-pedro-de-los-milagros',  'co-ant', 'San Pedro de los Milagros'),  -- DANE 05664
  ('co-ant-san-pedro-de-uraba',         'co-ant', 'San Pedro de Urabá'),  -- DANE 05665
  ('co-ant-san-rafael',                 'co-ant', 'San Rafael'),  -- DANE 05667
  ('co-ant-san-roque',                  'co-ant', 'San Roque'),  -- DANE 05670
  ('co-ant-san-vicente-ferrer',         'co-ant', 'San Vicente Ferrer'),  -- DANE 05674
  ('co-ant-santa-barbara',              'co-ant', 'Santa Bárbara'),  -- DANE 05679
  ('co-ant-santa-rosa-de-osos',         'co-ant', 'Santa Rosa de Osos'),  -- DANE 05686
  ('co-ant-santo-domingo',              'co-ant', 'Santo Domingo'),  -- DANE 05690
  ('co-ant-el-santuario',               'co-ant', 'El Santuario'),  -- DANE 05697
  ('co-ant-segovia',                    'co-ant', 'Segovia'),  -- DANE 05736
  ('co-ant-sonson',                     'co-ant', 'Sonsón'),  -- DANE 05756
  ('co-ant-sopetran',                   'co-ant', 'Sopetrán'),  -- DANE 05761
  ('co-ant-tamesis',                    'co-ant', 'Támesis'),  -- DANE 05789
  ('co-ant-taraza',                     'co-ant', 'Tarazá'),  -- DANE 05790
  ('co-ant-tarso',                      'co-ant', 'Tarso'),  -- DANE 05792
  ('co-ant-titiribi',                   'co-ant', 'Titiribí'),  -- DANE 05809
  ('co-ant-toledo',                     'co-ant', 'Toledo'),  -- DANE 05819
  ('co-ant-turbo',                      'co-ant', 'Turbo'),  -- DANE 05837
  ('co-ant-uramita',                    'co-ant', 'Uramita'),  -- DANE 05842
  ('co-ant-urrao',                      'co-ant', 'Urrao'),  -- DANE 05847
  ('co-ant-valdivia',                   'co-ant', 'Valdivia'),  -- DANE 05854
  ('co-ant-valparaiso',                 'co-ant', 'Valparaíso'),  -- DANE 05856
  ('co-ant-vegachi',                    'co-ant', 'Vegachí'),  -- DANE 05858
  ('co-ant-venecia',                    'co-ant', 'Venecia'),  -- DANE 05861
  ('co-ant-vigia-del-fuerte',           'co-ant', 'Vigía del Fuerte'),  -- DANE 05873
  ('co-ant-yali',                       'co-ant', 'Yalí'),  -- DANE 05885
  ('co-ant-yarumal',                    'co-ant', 'Yarumal'),  -- DANE 05887
  ('co-ant-yolombo',                    'co-ant', 'Yolombó'),  -- DANE 05890
  ('co-ant-yondo',                      'co-ant', 'Yondó'),  -- DANE 05893
  ('co-ant-zaragoza',                   'co-ant', 'Zaragoza')  -- DANE 05895
ON CONFLICT (id) DO NOTHING;

-- ATL · Atlántico (DANE 08) — 23 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-atl-barranquilla',      'co-atl', 'Barranquilla'),  -- DANE 08001
  ('co-atl-baranoa',           'co-atl', 'Baranoa'),  -- DANE 08078
  ('co-atl-campo-de-la-cruz',  'co-atl', 'Campo de la Cruz'),  -- DANE 08137
  ('co-atl-candelaria',        'co-atl', 'Candelaria'),  -- DANE 08141
  ('co-atl-galapa',            'co-atl', 'Galapa'),  -- DANE 08296
  ('co-atl-juan-de-acosta',    'co-atl', 'Juan de Acosta'),  -- DANE 08372
  ('co-atl-luruaco',           'co-atl', 'Luruaco'),  -- DANE 08421
  ('co-atl-malambo',           'co-atl', 'Malambo'),  -- DANE 08433
  ('co-atl-manati',            'co-atl', 'Manatí'),  -- DANE 08436
  ('co-atl-palmar-de-varela',  'co-atl', 'Palmar de Varela'),  -- DANE 08520
  ('co-atl-piojo',             'co-atl', 'Piojó'),  -- DANE 08549
  ('co-atl-polonuevo',         'co-atl', 'Polonuevo'),  -- DANE 08558
  ('co-atl-ponedera',          'co-atl', 'Ponedera'),  -- DANE 08560
  ('co-atl-puerto-colombia',   'co-atl', 'Puerto Colombia'),  -- DANE 08573
  ('co-atl-repelon',           'co-atl', 'Repelón'),  -- DANE 08606
  ('co-atl-sabanagrande',      'co-atl', 'Sabanagrande'),  -- DANE 08634
  ('co-atl-sabanalarga',       'co-atl', 'Sabanalarga'),  -- DANE 08638
  ('co-atl-santa-lucia',       'co-atl', 'Santa Lucía'),  -- DANE 08675
  ('co-atl-santo-tomas',       'co-atl', 'Santo Tomás'),  -- DANE 08685
  ('co-atl-soledad',           'co-atl', 'Soledad'),  -- DANE 08758
  ('co-atl-suan',              'co-atl', 'Suan'),  -- DANE 08770
  ('co-atl-tubara',            'co-atl', 'Tubará'),  -- DANE 08832
  ('co-atl-usiacuri',          'co-atl', 'Usiacurí')  -- DANE 08849
ON CONFLICT (id) DO NOTHING;

-- DC · Bogotá, D.c. (DANE 11) — 1 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-dc-bogota',  'co-dc', 'Bogotá, D.C.')  -- DANE 11001
ON CONFLICT (id) DO NOTHING;

-- BOL · Bolívar (DANE 13) — 46 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-bol-cartagena-de-indias',    'co-bol', 'Cartagena de Indias'),  -- DANE 13001
  ('co-bol-achi',                   'co-bol', 'Achí'),  -- DANE 13006
  ('co-bol-altos-del-rosario',      'co-bol', 'Altos del Rosario'),  -- DANE 13030
  ('co-bol-arenal',                 'co-bol', 'Arenal'),  -- DANE 13042
  ('co-bol-arjona',                 'co-bol', 'Arjona'),  -- DANE 13052
  ('co-bol-arroyohondo',            'co-bol', 'Arroyohondo'),  -- DANE 13062
  ('co-bol-barranco-de-loba',       'co-bol', 'Barranco de Loba'),  -- DANE 13074
  ('co-bol-calamar',                'co-bol', 'Calamar'),  -- DANE 13140
  ('co-bol-cantagallo',             'co-bol', 'Cantagallo'),  -- DANE 13160
  ('co-bol-cicuco',                 'co-bol', 'Cicuco'),  -- DANE 13188
  ('co-bol-cordoba',                'co-bol', 'Córdoba'),  -- DANE 13212
  ('co-bol-clemencia',              'co-bol', 'Clemencia'),  -- DANE 13222
  ('co-bol-el-carmen-de-bolivar',   'co-bol', 'El Carmen de Bolívar'),  -- DANE 13244
  ('co-bol-el-guamo',               'co-bol', 'El Guamo'),  -- DANE 13248
  ('co-bol-el-penon',               'co-bol', 'El Peñón'),  -- DANE 13268
  ('co-bol-hatillo-de-loba',        'co-bol', 'Hatillo de Loba'),  -- DANE 13300
  ('co-bol-magangue',               'co-bol', 'Magangué'),  -- DANE 13430
  ('co-bol-mahates',                'co-bol', 'Mahates'),  -- DANE 13433
  ('co-bol-margarita',              'co-bol', 'Margarita'),  -- DANE 13440
  ('co-bol-maria-la-baja',          'co-bol', 'María la Baja'),  -- DANE 13442
  ('co-bol-montecristo',            'co-bol', 'Montecristo'),  -- DANE 13458
  ('co-bol-santa-cruz-de-mompox',   'co-bol', 'Santa Cruz de Mompox'),  -- DANE 13468
  ('co-bol-morales',                'co-bol', 'Morales'),  -- DANE 13473
  ('co-bol-norosi',                 'co-bol', 'Norosí'),  -- DANE 13490
  ('co-bol-pinillos',               'co-bol', 'Pinillos'),  -- DANE 13549
  ('co-bol-regidor',                'co-bol', 'Regidor'),  -- DANE 13580
  ('co-bol-rio-viejo',              'co-bol', 'Río Viejo'),  -- DANE 13600
  ('co-bol-san-cristobal',          'co-bol', 'San Cristóbal'),  -- DANE 13620
  ('co-bol-san-estanislao',         'co-bol', 'San Estanislao'),  -- DANE 13647
  ('co-bol-san-fernando',           'co-bol', 'San Fernando'),  -- DANE 13650
  ('co-bol-san-jacinto',            'co-bol', 'San Jacinto'),  -- DANE 13654
  ('co-bol-san-jacinto-del-cauca',  'co-bol', 'San Jacinto del Cauca'),  -- DANE 13655
  ('co-bol-san-juan-nepomuceno',    'co-bol', 'San Juan Nepomuceno'),  -- DANE 13657
  ('co-bol-san-martin-de-loba',     'co-bol', 'San Martín de Loba'),  -- DANE 13667
  ('co-bol-san-pablo',              'co-bol', 'San Pablo'),  -- DANE 13670
  ('co-bol-santa-catalina',         'co-bol', 'Santa Catalina'),  -- DANE 13673
  ('co-bol-santa-rosa',             'co-bol', 'Santa Rosa'),  -- DANE 13683
  ('co-bol-santa-rosa-del-sur',     'co-bol', 'Santa Rosa del Sur'),  -- DANE 13688
  ('co-bol-simiti',                 'co-bol', 'Simití'),  -- DANE 13744
  ('co-bol-soplaviento',            'co-bol', 'Soplaviento'),  -- DANE 13760
  ('co-bol-talaigua-nuevo',         'co-bol', 'Talaigua Nuevo'),  -- DANE 13780
  ('co-bol-tiquisio',               'co-bol', 'Tiquisio'),  -- DANE 13810
  ('co-bol-turbaco',                'co-bol', 'Turbaco'),  -- DANE 13836
  ('co-bol-turbana',                'co-bol', 'Turbaná'),  -- DANE 13838
  ('co-bol-villanueva',             'co-bol', 'Villanueva'),  -- DANE 13873
  ('co-bol-zambrano',               'co-bol', 'Zambrano')  -- DANE 13894
ON CONFLICT (id) DO NOTHING;

-- BOY · Boyacá (DANE 15) — 123 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-boy-tunja',                  'co-boy', 'Tunja'),  -- DANE 15001
  ('co-boy-almeida',                'co-boy', 'Almeida'),  -- DANE 15022
  ('co-boy-aquitania',              'co-boy', 'Aquitania'),  -- DANE 15047
  ('co-boy-arcabuco',               'co-boy', 'Arcabuco'),  -- DANE 15051
  ('co-boy-belen',                  'co-boy', 'Belén'),  -- DANE 15087
  ('co-boy-berbeo',                 'co-boy', 'Berbeo'),  -- DANE 15090
  ('co-boy-beteitiva',              'co-boy', 'Betéitiva'),  -- DANE 15092
  ('co-boy-boavita',                'co-boy', 'Boavita'),  -- DANE 15097
  ('co-boy-boyaca',                 'co-boy', 'Boyacá'),  -- DANE 15104
  ('co-boy-briceno',                'co-boy', 'Briceño'),  -- DANE 15106
  ('co-boy-buenavista',             'co-boy', 'Buenavista'),  -- DANE 15109
  ('co-boy-busbanza',               'co-boy', 'Busbanzá'),  -- DANE 15114
  ('co-boy-caldas',                 'co-boy', 'Caldas'),  -- DANE 15131
  ('co-boy-campohermoso',           'co-boy', 'Campohermoso'),  -- DANE 15135
  ('co-boy-cerinza',                'co-boy', 'Cerinza'),  -- DANE 15162
  ('co-boy-chinavita',              'co-boy', 'Chinavita'),  -- DANE 15172
  ('co-boy-chiquinquira',           'co-boy', 'Chiquinquirá'),  -- DANE 15176
  ('co-boy-chiscas',                'co-boy', 'Chiscas'),  -- DANE 15180
  ('co-boy-chita',                  'co-boy', 'Chita'),  -- DANE 15183
  ('co-boy-chitaraque',             'co-boy', 'Chitaraque'),  -- DANE 15185
  ('co-boy-chivata',                'co-boy', 'Chivatá'),  -- DANE 15187
  ('co-boy-cienega',                'co-boy', 'Ciénega'),  -- DANE 15189
  ('co-boy-combita',                'co-boy', 'Cómbita'),  -- DANE 15204
  ('co-boy-coper',                  'co-boy', 'Coper'),  -- DANE 15212
  ('co-boy-corrales',               'co-boy', 'Corrales'),  -- DANE 15215
  ('co-boy-covarachia',             'co-boy', 'Covarachía'),  -- DANE 15218
  ('co-boy-cubara',                 'co-boy', 'Cubará'),  -- DANE 15223
  ('co-boy-cucaita',                'co-boy', 'Cucaita'),  -- DANE 15224
  ('co-boy-cuitiva',                'co-boy', 'Cuítiva'),  -- DANE 15226
  ('co-boy-chiquiza',               'co-boy', 'Chíquiza'),  -- DANE 15232
  ('co-boy-chivor',                 'co-boy', 'Chivor'),  -- DANE 15236
  ('co-boy-duitama',                'co-boy', 'Duitama'),  -- DANE 15238
  ('co-boy-el-cocuy',               'co-boy', 'El Cocuy'),  -- DANE 15244
  ('co-boy-el-espino',              'co-boy', 'El Espino'),  -- DANE 15248
  ('co-boy-firavitoba',             'co-boy', 'Firavitoba'),  -- DANE 15272
  ('co-boy-floresta',               'co-boy', 'Floresta'),  -- DANE 15276
  ('co-boy-gachantiva',             'co-boy', 'Gachantivá'),  -- DANE 15293
  ('co-boy-gameza',                 'co-boy', 'Gámeza'),  -- DANE 15296
  ('co-boy-garagoa',                'co-boy', 'Garagoa'),  -- DANE 15299
  ('co-boy-guacamayas',             'co-boy', 'Guacamayas'),  -- DANE 15317
  ('co-boy-guateque',               'co-boy', 'Guateque'),  -- DANE 15322
  ('co-boy-guayata',                'co-boy', 'Guayatá'),  -- DANE 15325
  ('co-boy-guican-de-la-sierra',    'co-boy', 'Güicán de la Sierra'),  -- DANE 15332
  ('co-boy-iza',                    'co-boy', 'Iza'),  -- DANE 15362
  ('co-boy-jenesano',               'co-boy', 'Jenesano'),  -- DANE 15367
  ('co-boy-jerico',                 'co-boy', 'Jericó'),  -- DANE 15368
  ('co-boy-labranzagrande',         'co-boy', 'Labranzagrande'),  -- DANE 15377
  ('co-boy-la-capilla',             'co-boy', 'La Capilla'),  -- DANE 15380
  ('co-boy-la-victoria',            'co-boy', 'La Victoria'),  -- DANE 15401
  ('co-boy-la-uvita',               'co-boy', 'La Uvita'),  -- DANE 15403
  ('co-boy-villa-de-leyva',         'co-boy', 'Villa de Leyva'),  -- DANE 15407
  ('co-boy-macanal',                'co-boy', 'Macanal'),  -- DANE 15425
  ('co-boy-maripi',                 'co-boy', 'Maripí'),  -- DANE 15442
  ('co-boy-miraflores',             'co-boy', 'Miraflores'),  -- DANE 15455
  ('co-boy-mongua',                 'co-boy', 'Mongua'),  -- DANE 15464
  ('co-boy-mongui',                 'co-boy', 'Monguí'),  -- DANE 15466
  ('co-boy-moniquira',              'co-boy', 'Moniquirá'),  -- DANE 15469
  ('co-boy-motavita',               'co-boy', 'Motavita'),  -- DANE 15476
  ('co-boy-muzo',                   'co-boy', 'Muzo'),  -- DANE 15480
  ('co-boy-nobsa',                  'co-boy', 'Nobsa'),  -- DANE 15491
  ('co-boy-nuevo-colon',            'co-boy', 'Nuevo Colón'),  -- DANE 15494
  ('co-boy-oicata',                 'co-boy', 'Oicatá'),  -- DANE 15500
  ('co-boy-otanche',                'co-boy', 'Otanche'),  -- DANE 15507
  ('co-boy-pachavita',              'co-boy', 'Pachavita'),  -- DANE 15511
  ('co-boy-paez',                   'co-boy', 'Páez'),  -- DANE 15514
  ('co-boy-paipa',                  'co-boy', 'Paipa'),  -- DANE 15516
  ('co-boy-pajarito',               'co-boy', 'Pajarito'),  -- DANE 15518
  ('co-boy-panqueba',               'co-boy', 'Panqueba'),  -- DANE 15522
  ('co-boy-pauna',                  'co-boy', 'Pauna'),  -- DANE 15531
  ('co-boy-paya',                   'co-boy', 'Paya'),  -- DANE 15533
  ('co-boy-paz-de-rio',             'co-boy', 'Paz de Río'),  -- DANE 15537
  ('co-boy-pesca',                  'co-boy', 'Pesca'),  -- DANE 15542
  ('co-boy-pisba',                  'co-boy', 'Pisba'),  -- DANE 15550
  ('co-boy-puerto-boyaca',          'co-boy', 'Puerto Boyacá'),  -- DANE 15572
  ('co-boy-quipama',                'co-boy', 'Quípama'),  -- DANE 15580
  ('co-boy-ramiriqui',              'co-boy', 'Ramiriquí'),  -- DANE 15599
  ('co-boy-raquira',                'co-boy', 'Ráquira'),  -- DANE 15600
  ('co-boy-rondon',                 'co-boy', 'Rondón'),  -- DANE 15621
  ('co-boy-saboya',                 'co-boy', 'Saboyá'),  -- DANE 15632
  ('co-boy-sachica',                'co-boy', 'Sáchica'),  -- DANE 15638
  ('co-boy-samaca',                 'co-boy', 'Samacá'),  -- DANE 15646
  ('co-boy-san-eduardo',            'co-boy', 'San Eduardo'),  -- DANE 15660
  ('co-boy-san-jose-de-pare',       'co-boy', 'San José de Pare'),  -- DANE 15664
  ('co-boy-san-luis-de-gaceno',     'co-boy', 'San Luis de Gaceno'),  -- DANE 15667
  ('co-boy-san-mateo',              'co-boy', 'San Mateo'),  -- DANE 15673
  ('co-boy-san-miguel-de-sema',     'co-boy', 'San Miguel de Sema'),  -- DANE 15676
  ('co-boy-san-pablo-de-borbur',    'co-boy', 'San Pablo de Borbur'),  -- DANE 15681
  ('co-boy-santana',                'co-boy', 'Santana'),  -- DANE 15686
  ('co-boy-santa-maria',            'co-boy', 'Santa María'),  -- DANE 15690
  ('co-boy-santa-rosa-de-viterbo',  'co-boy', 'Santa Rosa de Viterbo'),  -- DANE 15693
  ('co-boy-santa-sofia',            'co-boy', 'Santa Sofía'),  -- DANE 15696
  ('co-boy-sativanorte',            'co-boy', 'Sativanorte'),  -- DANE 15720
  ('co-boy-sativasur',              'co-boy', 'Sativasur'),  -- DANE 15723
  ('co-boy-siachoque',              'co-boy', 'Siachoque'),  -- DANE 15740
  ('co-boy-soata',                  'co-boy', 'Soatá'),  -- DANE 15753
  ('co-boy-socota',                 'co-boy', 'Socotá'),  -- DANE 15755
  ('co-boy-socha',                  'co-boy', 'Socha'),  -- DANE 15757
  ('co-boy-sogamoso',               'co-boy', 'Sogamoso'),  -- DANE 15759
  ('co-boy-somondoco',              'co-boy', 'Somondoco'),  -- DANE 15761
  ('co-boy-sora',                   'co-boy', 'Sora'),  -- DANE 15762
  ('co-boy-sotaquira',              'co-boy', 'Sotaquirá'),  -- DANE 15763
  ('co-boy-soraca',                 'co-boy', 'Soracá'),  -- DANE 15764
  ('co-boy-susacon',                'co-boy', 'Susacón'),  -- DANE 15774
  ('co-boy-sutamarchan',            'co-boy', 'Sutamarchán'),  -- DANE 15776
  ('co-boy-sutatenza',              'co-boy', 'Sutatenza'),  -- DANE 15778
  ('co-boy-tasco',                  'co-boy', 'Tasco'),  -- DANE 15790
  ('co-boy-tenza',                  'co-boy', 'Tenza'),  -- DANE 15798
  ('co-boy-tibana',                 'co-boy', 'Tibaná'),  -- DANE 15804
  ('co-boy-tibasosa',               'co-boy', 'Tibasosa'),  -- DANE 15806
  ('co-boy-tinjaca',                'co-boy', 'Tinjacá'),  -- DANE 15808
  ('co-boy-tipacoque',              'co-boy', 'Tipacoque'),  -- DANE 15810
  ('co-boy-toca',                   'co-boy', 'Toca'),  -- DANE 15814
  ('co-boy-togui',                  'co-boy', 'Togüí'),  -- DANE 15816
  ('co-boy-topaga',                 'co-boy', 'Tópaga'),  -- DANE 15820
  ('co-boy-tota',                   'co-boy', 'Tota'),  -- DANE 15822
  ('co-boy-tunungua',               'co-boy', 'Tununguá'),  -- DANE 15832
  ('co-boy-turmeque',               'co-boy', 'Turmequé'),  -- DANE 15835
  ('co-boy-tuta',                   'co-boy', 'Tuta'),  -- DANE 15837
  ('co-boy-tutaza',                 'co-boy', 'Tutazá'),  -- DANE 15839
  ('co-boy-umbita',                 'co-boy', 'Úmbita'),  -- DANE 15842
  ('co-boy-ventaquemada',           'co-boy', 'Ventaquemada'),  -- DANE 15861
  ('co-boy-viracacha',              'co-boy', 'Viracachá'),  -- DANE 15879
  ('co-boy-zetaquira',              'co-boy', 'Zetaquira')  -- DANE 15897
ON CONFLICT (id) DO NOTHING;

-- CAL · Caldas (DANE 17) — 27 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-cal-manizales',    'co-cal', 'Manizales'),  -- DANE 17001
  ('co-cal-aguadas',      'co-cal', 'Aguadas'),  -- DANE 17013
  ('co-cal-anserma',      'co-cal', 'Anserma'),  -- DANE 17042
  ('co-cal-aranzazu',     'co-cal', 'Aranzazu'),  -- DANE 17050
  ('co-cal-belalcazar',   'co-cal', 'Belalcázar'),  -- DANE 17088
  ('co-cal-chinchina',    'co-cal', 'Chinchiná'),  -- DANE 17174
  ('co-cal-filadelfia',   'co-cal', 'Filadelfia'),  -- DANE 17272
  ('co-cal-la-dorada',    'co-cal', 'La Dorada'),  -- DANE 17380
  ('co-cal-la-merced',    'co-cal', 'La Merced'),  -- DANE 17388
  ('co-cal-manzanares',   'co-cal', 'Manzanares'),  -- DANE 17433
  ('co-cal-marmato',      'co-cal', 'Marmato'),  -- DANE 17442
  ('co-cal-marquetalia',  'co-cal', 'Marquetalia'),  -- DANE 17444
  ('co-cal-marulanda',    'co-cal', 'Marulanda'),  -- DANE 17446
  ('co-cal-neira',        'co-cal', 'Neira'),  -- DANE 17486
  ('co-cal-norcasia',     'co-cal', 'Norcasia'),  -- DANE 17495
  ('co-cal-pacora',       'co-cal', 'Pácora'),  -- DANE 17513
  ('co-cal-palestina',    'co-cal', 'Palestina'),  -- DANE 17524
  ('co-cal-pensilvania',  'co-cal', 'Pensilvania'),  -- DANE 17541
  ('co-cal-riosucio',     'co-cal', 'Riosucio'),  -- DANE 17614
  ('co-cal-risaralda',    'co-cal', 'Risaralda'),  -- DANE 17616
  ('co-cal-salamina',     'co-cal', 'Salamina'),  -- DANE 17653
  ('co-cal-samana',       'co-cal', 'Samaná'),  -- DANE 17662
  ('co-cal-san-jose',     'co-cal', 'San José'),  -- DANE 17665
  ('co-cal-supia',        'co-cal', 'Supía'),  -- DANE 17777
  ('co-cal-victoria',     'co-cal', 'Victoria'),  -- DANE 17867
  ('co-cal-villamaria',   'co-cal', 'Villamaría'),  -- DANE 17873
  ('co-cal-viterbo',      'co-cal', 'Viterbo')  -- DANE 17877
ON CONFLICT (id) DO NOTHING;

-- CAQ · Caquetá (DANE 18) — 16 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-caq-florencia',               'co-caq', 'Florencia'),  -- DANE 18001
  ('co-caq-albania',                 'co-caq', 'Albania'),  -- DANE 18029
  ('co-caq-belen-de-los-andaquies',  'co-caq', 'Belén de los Andaquíes'),  -- DANE 18094
  ('co-caq-cartagena-del-chaira',    'co-caq', 'Cartagena del Chairá'),  -- DANE 18150
  ('co-caq-curillo',                 'co-caq', 'Curillo'),  -- DANE 18205
  ('co-caq-el-doncello',             'co-caq', 'El Doncello'),  -- DANE 18247
  ('co-caq-el-paujil',               'co-caq', 'El Paujíl'),  -- DANE 18256
  ('co-caq-la-montanita',            'co-caq', 'La Montañita'),  -- DANE 18410
  ('co-caq-milan',                   'co-caq', 'Milán'),  -- DANE 18460
  ('co-caq-morelia',                 'co-caq', 'Morelia'),  -- DANE 18479
  ('co-caq-puerto-rico',             'co-caq', 'Puerto Rico'),  -- DANE 18592
  ('co-caq-san-jose-del-fragua',     'co-caq', 'San José del Fragua'),  -- DANE 18610
  ('co-caq-san-vicente-del-caguan',  'co-caq', 'San Vicente del Caguán'),  -- DANE 18753
  ('co-caq-solano',                  'co-caq', 'Solano'),  -- DANE 18756
  ('co-caq-solita',                  'co-caq', 'Solita'),  -- DANE 18785
  ('co-caq-valparaiso',              'co-caq', 'Valparaíso')  -- DANE 18860
ON CONFLICT (id) DO NOTHING;

-- CAU · Cauca (DANE 19) — 42 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-cau-popayan',                 'co-cau', 'Popayán'),  -- DANE 19001
  ('co-cau-almaguer',                'co-cau', 'Almaguer'),  -- DANE 19022
  ('co-cau-argelia',                 'co-cau', 'Argelia'),  -- DANE 19050
  ('co-cau-balboa',                  'co-cau', 'Balboa'),  -- DANE 19075
  ('co-cau-bolivar',                 'co-cau', 'Bolívar'),  -- DANE 19100
  ('co-cau-buenos-aires',            'co-cau', 'Buenos Aires'),  -- DANE 19110
  ('co-cau-cajibio',                 'co-cau', 'Cajibío'),  -- DANE 19130
  ('co-cau-caldono',                 'co-cau', 'Caldono'),  -- DANE 19137
  ('co-cau-caloto',                  'co-cau', 'Caloto'),  -- DANE 19142
  ('co-cau-corinto',                 'co-cau', 'Corinto'),  -- DANE 19212
  ('co-cau-el-tambo',                'co-cau', 'El Tambo'),  -- DANE 19256
  ('co-cau-florencia',               'co-cau', 'Florencia'),  -- DANE 19290
  ('co-cau-guachene',                'co-cau', 'Guachené'),  -- DANE 19300
  ('co-cau-guapi',                   'co-cau', 'Guapi'),  -- DANE 19318
  ('co-cau-inza',                    'co-cau', 'Inzá'),  -- DANE 19355
  ('co-cau-jambalo',                 'co-cau', 'Jambaló'),  -- DANE 19364
  ('co-cau-la-sierra',               'co-cau', 'La Sierra'),  -- DANE 19392
  ('co-cau-la-vega',                 'co-cau', 'La Vega'),  -- DANE 19397
  ('co-cau-lopez-de-micay',          'co-cau', 'López de Micay'),  -- DANE 19418
  ('co-cau-mercaderes',              'co-cau', 'Mercaderes'),  -- DANE 19450
  ('co-cau-miranda',                 'co-cau', 'Miranda'),  -- DANE 19455
  ('co-cau-morales',                 'co-cau', 'Morales'),  -- DANE 19473
  ('co-cau-padilla',                 'co-cau', 'Padilla'),  -- DANE 19513
  ('co-cau-paez',                    'co-cau', 'Páez'),  -- DANE 19517
  ('co-cau-patia',                   'co-cau', 'Patía'),  -- DANE 19532
  ('co-cau-piamonte',                'co-cau', 'Piamonte'),  -- DANE 19533
  ('co-cau-piendamo-tunia',          'co-cau', 'Piendamó - Tunía'),  -- DANE 19548
  ('co-cau-puerto-tejada',           'co-cau', 'Puerto Tejada'),  -- DANE 19573
  ('co-cau-purace',                  'co-cau', 'Puracé'),  -- DANE 19585
  ('co-cau-rosas',                   'co-cau', 'Rosas'),  -- DANE 19622
  ('co-cau-san-sebastian',           'co-cau', 'San Sebastián'),  -- DANE 19693
  ('co-cau-santander-de-quilichao',  'co-cau', 'Santander de Quilichao'),  -- DANE 19698
  ('co-cau-santa-rosa',              'co-cau', 'Santa Rosa'),  -- DANE 19701
  ('co-cau-silvia',                  'co-cau', 'Silvia'),  -- DANE 19743
  ('co-cau-sotara-paispamba',        'co-cau', 'Sotará - Paispamba'),  -- DANE 19760
  ('co-cau-suarez',                  'co-cau', 'Suárez'),  -- DANE 19780
  ('co-cau-sucre',                   'co-cau', 'Sucre'),  -- DANE 19785
  ('co-cau-timbio',                  'co-cau', 'Timbío'),  -- DANE 19807
  ('co-cau-timbiqui',                'co-cau', 'Timbiquí'),  -- DANE 19809
  ('co-cau-toribio',                 'co-cau', 'Toribío'),  -- DANE 19821
  ('co-cau-totoro',                  'co-cau', 'Totoró'),  -- DANE 19824
  ('co-cau-villa-rica',              'co-cau', 'Villa Rica')  -- DANE 19845
ON CONFLICT (id) DO NOTHING;

-- CES · Cesar (DANE 20) — 25 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-ces-valledupar',                'co-ces', 'Valledupar'),  -- DANE 20001
  ('co-ces-aguachica',                 'co-ces', 'Aguachica'),  -- DANE 20011
  ('co-ces-agustin-codazzi',           'co-ces', 'Agustín Codazzi'),  -- DANE 20013
  ('co-ces-astrea',                    'co-ces', 'Astrea'),  -- DANE 20032
  ('co-ces-becerril',                  'co-ces', 'Becerril'),  -- DANE 20045
  ('co-ces-bosconia',                  'co-ces', 'Bosconia'),  -- DANE 20060
  ('co-ces-chimichagua',               'co-ces', 'Chimichagua'),  -- DANE 20175
  ('co-ces-chiriguana',                'co-ces', 'Chiriguaná'),  -- DANE 20178
  ('co-ces-curumani',                  'co-ces', 'Curumaní'),  -- DANE 20228
  ('co-ces-el-copey',                  'co-ces', 'El Copey'),  -- DANE 20238
  ('co-ces-el-paso',                   'co-ces', 'El Paso'),  -- DANE 20250
  ('co-ces-gamarra',                   'co-ces', 'Gamarra'),  -- DANE 20295
  ('co-ces-gonzalez',                  'co-ces', 'González'),  -- DANE 20310
  ('co-ces-la-gloria',                 'co-ces', 'La Gloria'),  -- DANE 20383
  ('co-ces-la-jagua-de-ibirico',       'co-ces', 'La Jagua de Ibirico'),  -- DANE 20400
  ('co-ces-manaure-balcon-del-cesar',  'co-ces', 'Manaure Balcón del Cesar'),  -- DANE 20443
  ('co-ces-pailitas',                  'co-ces', 'Pailitas'),  -- DANE 20517
  ('co-ces-pelaya',                    'co-ces', 'Pelaya'),  -- DANE 20550
  ('co-ces-pueblo-bello',              'co-ces', 'Pueblo Bello'),  -- DANE 20570
  ('co-ces-rio-de-oro',                'co-ces', 'Río de Oro'),  -- DANE 20614
  ('co-ces-la-paz',                    'co-ces', 'La Paz'),  -- DANE 20621
  ('co-ces-san-alberto',               'co-ces', 'San Alberto'),  -- DANE 20710
  ('co-ces-san-diego',                 'co-ces', 'San Diego'),  -- DANE 20750
  ('co-ces-san-martin',                'co-ces', 'San Martín'),  -- DANE 20770
  ('co-ces-tamalameque',               'co-ces', 'Tamalameque')  -- DANE 20787
ON CONFLICT (id) DO NOTHING;

-- COR · Córdoba (DANE 23) — 30 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-cor-monteria',                   'co-cor', 'Montería'),  -- DANE 23001
  ('co-cor-ayapel',                     'co-cor', 'Ayapel'),  -- DANE 23068
  ('co-cor-buenavista',                 'co-cor', 'Buenavista'),  -- DANE 23079
  ('co-cor-canalete',                   'co-cor', 'Canalete'),  -- DANE 23090
  ('co-cor-cerete',                     'co-cor', 'Cereté'),  -- DANE 23162
  ('co-cor-chima',                      'co-cor', 'Chimá'),  -- DANE 23168
  ('co-cor-chinu',                      'co-cor', 'Chinú'),  -- DANE 23182
  ('co-cor-cienaga-de-oro',             'co-cor', 'Ciénaga de Oro'),  -- DANE 23189
  ('co-cor-cotorra',                    'co-cor', 'Cotorra'),  -- DANE 23300
  ('co-cor-la-apartada',                'co-cor', 'La Apartada'),  -- DANE 23350
  ('co-cor-lorica',                     'co-cor', 'Lorica'),  -- DANE 23417
  ('co-cor-los-cordobas',               'co-cor', 'Los Córdobas'),  -- DANE 23419
  ('co-cor-momil',                      'co-cor', 'Momil'),  -- DANE 23464
  ('co-cor-montelibano',                'co-cor', 'Montelíbano'),  -- DANE 23466
  ('co-cor-monitos',                    'co-cor', 'Moñitos'),  -- DANE 23500
  ('co-cor-planeta-rica',               'co-cor', 'Planeta Rica'),  -- DANE 23555
  ('co-cor-pueblo-nuevo',               'co-cor', 'Pueblo Nuevo'),  -- DANE 23570
  ('co-cor-puerto-escondido',           'co-cor', 'Puerto Escondido'),  -- DANE 23574
  ('co-cor-puerto-libertador',          'co-cor', 'Puerto Libertador'),  -- DANE 23580
  ('co-cor-purisima-de-la-concepcion',  'co-cor', 'Purísima de la Concepción'),  -- DANE 23586
  ('co-cor-sahagun',                    'co-cor', 'Sahagún'),  -- DANE 23660
  ('co-cor-san-andres-de-sotavento',    'co-cor', 'San Andrés de Sotavento'),  -- DANE 23670
  ('co-cor-san-antero',                 'co-cor', 'San Antero'),  -- DANE 23672
  ('co-cor-san-bernardo-del-viento',    'co-cor', 'San Bernardo del Viento'),  -- DANE 23675
  ('co-cor-san-carlos',                 'co-cor', 'San Carlos'),  -- DANE 23678
  ('co-cor-san-jose-de-ure',            'co-cor', 'San José de Uré'),  -- DANE 23682
  ('co-cor-san-pelayo',                 'co-cor', 'San Pelayo'),  -- DANE 23686
  ('co-cor-tierralta',                  'co-cor', 'Tierralta'),  -- DANE 23807
  ('co-cor-tuchin',                     'co-cor', 'Tuchín'),  -- DANE 23815
  ('co-cor-valencia',                   'co-cor', 'Valencia')  -- DANE 23855
ON CONFLICT (id) DO NOTHING;

-- CUN · Cundinamarca (DANE 25) — 116 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-cun-agua-de-dios',                 'co-cun', 'Agua de Dios'),  -- DANE 25001
  ('co-cun-alban',                        'co-cun', 'Albán'),  -- DANE 25019
  ('co-cun-anapoima',                     'co-cun', 'Anapoima'),  -- DANE 25035
  ('co-cun-anolaima',                     'co-cun', 'Anolaima'),  -- DANE 25040
  ('co-cun-arbelaez',                     'co-cun', 'Arbeláez'),  -- DANE 25053
  ('co-cun-beltran',                      'co-cun', 'Beltrán'),  -- DANE 25086
  ('co-cun-bituima',                      'co-cun', 'Bituima'),  -- DANE 25095
  ('co-cun-bojaca',                       'co-cun', 'Bojacá'),  -- DANE 25099
  ('co-cun-cabrera',                      'co-cun', 'Cabrera'),  -- DANE 25120
  ('co-cun-cachipay',                     'co-cun', 'Cachipay'),  -- DANE 25123
  ('co-cun-cajica',                       'co-cun', 'Cajicá'),  -- DANE 25126
  ('co-cun-caparrapi',                    'co-cun', 'Caparrapí'),  -- DANE 25148
  ('co-cun-caqueza',                      'co-cun', 'Cáqueza'),  -- DANE 25151
  ('co-cun-carmen-de-carupa',             'co-cun', 'Carmen de Carupa'),  -- DANE 25154
  ('co-cun-chaguani',                     'co-cun', 'Chaguaní'),  -- DANE 25168
  ('co-cun-chia',                         'co-cun', 'Chía'),  -- DANE 25175
  ('co-cun-chipaque',                     'co-cun', 'Chipaque'),  -- DANE 25178
  ('co-cun-choachi',                      'co-cun', 'Choachí'),  -- DANE 25181
  ('co-cun-choconta',                     'co-cun', 'Chocontá'),  -- DANE 25183
  ('co-cun-cogua',                        'co-cun', 'Cogua'),  -- DANE 25200
  ('co-cun-cota',                         'co-cun', 'Cota'),  -- DANE 25214
  ('co-cun-cucunuba',                     'co-cun', 'Cucunubá'),  -- DANE 25224
  ('co-cun-el-colegio',                   'co-cun', 'El Colegio'),  -- DANE 25245
  ('co-cun-el-penon',                     'co-cun', 'El Peñón'),  -- DANE 25258
  ('co-cun-el-rosal',                     'co-cun', 'El Rosal'),  -- DANE 25260
  ('co-cun-facatativa',                   'co-cun', 'Facatativá'),  -- DANE 25269
  ('co-cun-fomeque',                      'co-cun', 'Fómeque'),  -- DANE 25279
  ('co-cun-fosca',                        'co-cun', 'Fosca'),  -- DANE 25281
  ('co-cun-funza',                        'co-cun', 'Funza'),  -- DANE 25286
  ('co-cun-fuquene',                      'co-cun', 'Fúquene'),  -- DANE 25288
  ('co-cun-fusagasuga',                   'co-cun', 'Fusagasugá'),  -- DANE 25290
  ('co-cun-gachala',                      'co-cun', 'Gachalá'),  -- DANE 25293
  ('co-cun-gachancipa',                   'co-cun', 'Gachancipá'),  -- DANE 25295
  ('co-cun-gacheta',                      'co-cun', 'Gachetá'),  -- DANE 25297
  ('co-cun-gama',                         'co-cun', 'Gama'),  -- DANE 25299
  ('co-cun-girardot',                     'co-cun', 'Girardot'),  -- DANE 25307
  ('co-cun-granada',                      'co-cun', 'Granada'),  -- DANE 25312
  ('co-cun-guacheta',                     'co-cun', 'Guachetá'),  -- DANE 25317
  ('co-cun-guaduas',                      'co-cun', 'Guaduas'),  -- DANE 25320
  ('co-cun-guasca',                       'co-cun', 'Guasca'),  -- DANE 25322
  ('co-cun-guataqui',                     'co-cun', 'Guataquí'),  -- DANE 25324
  ('co-cun-guatavita',                    'co-cun', 'Guatavita'),  -- DANE 25326
  ('co-cun-guayabal-de-siquima',          'co-cun', 'Guayabal de Síquima'),  -- DANE 25328
  ('co-cun-guayabetal',                   'co-cun', 'Guayabetal'),  -- DANE 25335
  ('co-cun-gutierrez',                    'co-cun', 'Gutiérrez'),  -- DANE 25339
  ('co-cun-jerusalen',                    'co-cun', 'Jerusalén'),  -- DANE 25368
  ('co-cun-junin',                        'co-cun', 'Junín'),  -- DANE 25372
  ('co-cun-la-calera',                    'co-cun', 'La Calera'),  -- DANE 25377
  ('co-cun-la-mesa',                      'co-cun', 'La Mesa'),  -- DANE 25386
  ('co-cun-la-palma',                     'co-cun', 'La Palma'),  -- DANE 25394
  ('co-cun-la-pena',                      'co-cun', 'La Peña'),  -- DANE 25398
  ('co-cun-la-vega',                      'co-cun', 'La Vega'),  -- DANE 25402
  ('co-cun-lenguazaque',                  'co-cun', 'Lenguazaque'),  -- DANE 25407
  ('co-cun-macheta',                      'co-cun', 'Machetá'),  -- DANE 25426
  ('co-cun-madrid',                       'co-cun', 'Madrid'),  -- DANE 25430
  ('co-cun-manta',                        'co-cun', 'Manta'),  -- DANE 25436
  ('co-cun-medina',                       'co-cun', 'Medina'),  -- DANE 25438
  ('co-cun-mosquera',                     'co-cun', 'Mosquera'),  -- DANE 25473
  ('co-cun-narino',                       'co-cun', 'Nariño'),  -- DANE 25483
  ('co-cun-nemocon',                      'co-cun', 'Nemocón'),  -- DANE 25486
  ('co-cun-nilo',                         'co-cun', 'Nilo'),  -- DANE 25488
  ('co-cun-nimaima',                      'co-cun', 'Nimaima'),  -- DANE 25489
  ('co-cun-nocaima',                      'co-cun', 'Nocaima'),  -- DANE 25491
  ('co-cun-venecia',                      'co-cun', 'Venecia'),  -- DANE 25506
  ('co-cun-pacho',                        'co-cun', 'Pacho'),  -- DANE 25513
  ('co-cun-paime',                        'co-cun', 'Paime'),  -- DANE 25518
  ('co-cun-pandi',                        'co-cun', 'Pandi'),  -- DANE 25524
  ('co-cun-paratebueno',                  'co-cun', 'Paratebueno'),  -- DANE 25530
  ('co-cun-pasca',                        'co-cun', 'Pasca'),  -- DANE 25535
  ('co-cun-puerto-salgar',                'co-cun', 'Puerto Salgar'),  -- DANE 25572
  ('co-cun-puli',                         'co-cun', 'Pulí'),  -- DANE 25580
  ('co-cun-quebradanegra',                'co-cun', 'Quebradanegra'),  -- DANE 25592
  ('co-cun-quetame',                      'co-cun', 'Quetame'),  -- DANE 25594
  ('co-cun-quipile',                      'co-cun', 'Quipile'),  -- DANE 25596
  ('co-cun-apulo',                        'co-cun', 'Apulo'),  -- DANE 25599
  ('co-cun-ricaurte',                     'co-cun', 'Ricaurte'),  -- DANE 25612
  ('co-cun-san-antonio-del-tequendama',   'co-cun', 'San Antonio del Tequendama'),  -- DANE 25645
  ('co-cun-san-bernardo',                 'co-cun', 'San Bernardo'),  -- DANE 25649
  ('co-cun-san-cayetano',                 'co-cun', 'San Cayetano'),  -- DANE 25653
  ('co-cun-san-francisco',                'co-cun', 'San Francisco'),  -- DANE 25658
  ('co-cun-san-juan-de-rioseco',          'co-cun', 'San Juan de Rioseco'),  -- DANE 25662
  ('co-cun-sasaima',                      'co-cun', 'Sasaima'),  -- DANE 25718
  ('co-cun-sesquile',                     'co-cun', 'Sesquilé'),  -- DANE 25736
  ('co-cun-sibate',                       'co-cun', 'Sibaté'),  -- DANE 25740
  ('co-cun-silvania',                     'co-cun', 'Silvania'),  -- DANE 25743
  ('co-cun-simijaca',                     'co-cun', 'Simijaca'),  -- DANE 25745
  ('co-cun-soacha',                       'co-cun', 'Soacha'),  -- DANE 25754
  ('co-cun-sopo',                         'co-cun', 'Sopó'),  -- DANE 25758
  ('co-cun-subachoque',                   'co-cun', 'Subachoque'),  -- DANE 25769
  ('co-cun-suesca',                       'co-cun', 'Suesca'),  -- DANE 25772
  ('co-cun-supata',                       'co-cun', 'Supatá'),  -- DANE 25777
  ('co-cun-susa',                         'co-cun', 'Susa'),  -- DANE 25779
  ('co-cun-sutatausa',                    'co-cun', 'Sutatausa'),  -- DANE 25781
  ('co-cun-tabio',                        'co-cun', 'Tabio'),  -- DANE 25785
  ('co-cun-tausa',                        'co-cun', 'Tausa'),  -- DANE 25793
  ('co-cun-tena',                         'co-cun', 'Tena'),  -- DANE 25797
  ('co-cun-tenjo',                        'co-cun', 'Tenjo'),  -- DANE 25799
  ('co-cun-tibacuy',                      'co-cun', 'Tibacuy'),  -- DANE 25805
  ('co-cun-tibirita',                     'co-cun', 'Tibirita'),  -- DANE 25807
  ('co-cun-tocaima',                      'co-cun', 'Tocaima'),  -- DANE 25815
  ('co-cun-tocancipa',                    'co-cun', 'Tocancipá'),  -- DANE 25817
  ('co-cun-topaipi',                      'co-cun', 'Topaipí'),  -- DANE 25823
  ('co-cun-ubala',                        'co-cun', 'Ubalá'),  -- DANE 25839
  ('co-cun-ubaque',                       'co-cun', 'Ubaque'),  -- DANE 25841
  ('co-cun-villa-de-san-diego-de-ubate',  'co-cun', 'Villa de San Diego de Ubaté'),  -- DANE 25843
  ('co-cun-une',                          'co-cun', 'Une'),  -- DANE 25845
  ('co-cun-utica',                        'co-cun', 'Útica'),  -- DANE 25851
  ('co-cun-vergara',                      'co-cun', 'Vergara'),  -- DANE 25862
  ('co-cun-viani',                        'co-cun', 'Vianí'),  -- DANE 25867
  ('co-cun-villagomez',                   'co-cun', 'Villagómez'),  -- DANE 25871
  ('co-cun-villapinzon',                  'co-cun', 'Villapinzón'),  -- DANE 25873
  ('co-cun-villeta',                      'co-cun', 'Villeta'),  -- DANE 25875
  ('co-cun-viota',                        'co-cun', 'Viotá'),  -- DANE 25878
  ('co-cun-yacopi',                       'co-cun', 'Yacopí'),  -- DANE 25885
  ('co-cun-zipacon',                      'co-cun', 'Zipacón'),  -- DANE 25898
  ('co-cun-zipaquira',                    'co-cun', 'Zipaquirá')  -- DANE 25899
ON CONFLICT (id) DO NOTHING;

-- CHO · Chocó (DANE 27) — 31 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-cho-quibdo',                   'co-cho', 'Quibdó'),  -- DANE 27001
  ('co-cho-acandi',                   'co-cho', 'Acandí'),  -- DANE 27006
  ('co-cho-alto-baudo',               'co-cho', 'Alto Baudó'),  -- DANE 27025
  ('co-cho-atrato',                   'co-cho', 'Atrato'),  -- DANE 27050
  ('co-cho-bagado',                   'co-cho', 'Bagadó'),  -- DANE 27073
  ('co-cho-bahia-solano',             'co-cho', 'Bahía Solano'),  -- DANE 27075
  ('co-cho-bajo-baudo',               'co-cho', 'Bajo Baudó'),  -- DANE 27077
  ('co-cho-bojaya',                   'co-cho', 'Bojayá'),  -- DANE 27099
  ('co-cho-el-canton-del-san-pablo',  'co-cho', 'El Cantón del San Pablo'),  -- DANE 27135
  ('co-cho-carmen-del-darien',        'co-cho', 'Carmen del Darién'),  -- DANE 27150
  ('co-cho-certegui',                 'co-cho', 'Cértegui'),  -- DANE 27160
  ('co-cho-condoto',                  'co-cho', 'Condoto'),  -- DANE 27205
  ('co-cho-el-carmen-de-atrato',      'co-cho', 'El Carmen de Atrato'),  -- DANE 27245
  ('co-cho-el-litoral-del-san-juan',  'co-cho', 'El Litoral del San Juan'),  -- DANE 27250
  ('co-cho-istmina',                  'co-cho', 'Istmina'),  -- DANE 27361
  ('co-cho-jurado',                   'co-cho', 'Juradó'),  -- DANE 27372
  ('co-cho-lloro',                    'co-cho', 'Lloró'),  -- DANE 27413
  ('co-cho-medio-atrato',             'co-cho', 'Medio Atrato'),  -- DANE 27425
  ('co-cho-medio-baudo',              'co-cho', 'Medio Baudó'),  -- DANE 27430
  ('co-cho-medio-san-juan',           'co-cho', 'Medio San Juan'),  -- DANE 27450
  ('co-cho-novita',                   'co-cho', 'Nóvita'),  -- DANE 27491
  ('co-cho-nuevo-belen-de-bajira',    'co-cho', 'Nuevo Belén de Bajirá'),  -- DANE 27493
  ('co-cho-nuqui',                    'co-cho', 'Nuquí'),  -- DANE 27495
  ('co-cho-rio-iro',                  'co-cho', 'Río Iró'),  -- DANE 27580
  ('co-cho-rio-quito',                'co-cho', 'Río Quito'),  -- DANE 27600
  ('co-cho-riosucio',                 'co-cho', 'Riosucio'),  -- DANE 27615
  ('co-cho-san-jose-del-palmar',      'co-cho', 'San José del Palmar'),  -- DANE 27660
  ('co-cho-sipi',                     'co-cho', 'Sipí'),  -- DANE 27745
  ('co-cho-tado',                     'co-cho', 'Tadó'),  -- DANE 27787
  ('co-cho-unguia',                   'co-cho', 'Unguía'),  -- DANE 27800
  ('co-cho-union-panamericana',       'co-cho', 'Unión Panamericana')  -- DANE 27810
ON CONFLICT (id) DO NOTHING;

-- HUI · Huila (DANE 41) — 37 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-hui-neiva',         'co-hui', 'Neiva'),  -- DANE 41001
  ('co-hui-acevedo',       'co-hui', 'Acevedo'),  -- DANE 41006
  ('co-hui-agrado',        'co-hui', 'Agrado'),  -- DANE 41013
  ('co-hui-aipe',          'co-hui', 'Aipe'),  -- DANE 41016
  ('co-hui-algeciras',     'co-hui', 'Algeciras'),  -- DANE 41020
  ('co-hui-altamira',      'co-hui', 'Altamira'),  -- DANE 41026
  ('co-hui-baraya',        'co-hui', 'Baraya'),  -- DANE 41078
  ('co-hui-campoalegre',   'co-hui', 'Campoalegre'),  -- DANE 41132
  ('co-hui-colombia',      'co-hui', 'Colombia'),  -- DANE 41206
  ('co-hui-elias',         'co-hui', 'Elías'),  -- DANE 41244
  ('co-hui-garzon',        'co-hui', 'Garzón'),  -- DANE 41298
  ('co-hui-gigante',       'co-hui', 'Gigante'),  -- DANE 41306
  ('co-hui-guadalupe',     'co-hui', 'Guadalupe'),  -- DANE 41319
  ('co-hui-hobo',          'co-hui', 'Hobo'),  -- DANE 41349
  ('co-hui-iquira',        'co-hui', 'Íquira'),  -- DANE 41357
  ('co-hui-isnos',         'co-hui', 'Isnos'),  -- DANE 41359
  ('co-hui-la-argentina',  'co-hui', 'La Argentina'),  -- DANE 41378
  ('co-hui-la-plata',      'co-hui', 'La Plata'),  -- DANE 41396
  ('co-hui-nataga',        'co-hui', 'Nátaga'),  -- DANE 41483
  ('co-hui-oporapa',       'co-hui', 'Oporapa'),  -- DANE 41503
  ('co-hui-paicol',        'co-hui', 'Paicol'),  -- DANE 41518
  ('co-hui-palermo',       'co-hui', 'Palermo'),  -- DANE 41524
  ('co-hui-palestina',     'co-hui', 'Palestina'),  -- DANE 41530
  ('co-hui-pital',         'co-hui', 'Pital'),  -- DANE 41548
  ('co-hui-pitalito',      'co-hui', 'Pitalito'),  -- DANE 41551
  ('co-hui-rivera',        'co-hui', 'Rivera'),  -- DANE 41615
  ('co-hui-saladoblanco',  'co-hui', 'Saladoblanco'),  -- DANE 41660
  ('co-hui-san-agustin',   'co-hui', 'San Agustín'),  -- DANE 41668
  ('co-hui-santa-maria',   'co-hui', 'Santa María'),  -- DANE 41676
  ('co-hui-suaza',         'co-hui', 'Suaza'),  -- DANE 41770
  ('co-hui-tarqui',        'co-hui', 'Tarqui'),  -- DANE 41791
  ('co-hui-tesalia',       'co-hui', 'Tesalia'),  -- DANE 41797
  ('co-hui-tello',         'co-hui', 'Tello'),  -- DANE 41799
  ('co-hui-teruel',        'co-hui', 'Teruel'),  -- DANE 41801
  ('co-hui-timana',        'co-hui', 'Timaná'),  -- DANE 41807
  ('co-hui-villavieja',    'co-hui', 'Villavieja'),  -- DANE 41872
  ('co-hui-yaguara',       'co-hui', 'Yaguará')  -- DANE 41885
ON CONFLICT (id) DO NOTHING;

-- LAG · La Guajira (DANE 44) — 15 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-lag-riohacha',            'co-lag', 'Riohacha'),  -- DANE 44001
  ('co-lag-albania',             'co-lag', 'Albania'),  -- DANE 44035
  ('co-lag-barrancas',           'co-lag', 'Barrancas'),  -- DANE 44078
  ('co-lag-dibulla',             'co-lag', 'Dibulla'),  -- DANE 44090
  ('co-lag-distraccion',         'co-lag', 'Distracción'),  -- DANE 44098
  ('co-lag-el-molino',           'co-lag', 'El Molino'),  -- DANE 44110
  ('co-lag-fonseca',             'co-lag', 'Fonseca'),  -- DANE 44279
  ('co-lag-hatonuevo',           'co-lag', 'Hatonuevo'),  -- DANE 44378
  ('co-lag-la-jagua-del-pilar',  'co-lag', 'La Jagua del Pilar'),  -- DANE 44420
  ('co-lag-maicao',              'co-lag', 'Maicao'),  -- DANE 44430
  ('co-lag-manaure',             'co-lag', 'Manaure'),  -- DANE 44560
  ('co-lag-san-juan-del-cesar',  'co-lag', 'San Juan del Cesar'),  -- DANE 44650
  ('co-lag-uribia',              'co-lag', 'Uribia'),  -- DANE 44847
  ('co-lag-urumita',             'co-lag', 'Urumita'),  -- DANE 44855
  ('co-lag-villanueva',          'co-lag', 'Villanueva')  -- DANE 44874
ON CONFLICT (id) DO NOTHING;

-- MAG · Magdalena (DANE 47) — 30 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-mag-santa-marta',                  'co-mag', 'Santa Marta'),  -- DANE 47001
  ('co-mag-algarrobo',                    'co-mag', 'Algarrobo'),  -- DANE 47030
  ('co-mag-aracataca',                    'co-mag', 'Aracataca'),  -- DANE 47053
  ('co-mag-ariguani',                     'co-mag', 'Ariguaní'),  -- DANE 47058
  ('co-mag-cerro-de-san-antonio',         'co-mag', 'Cerro de San Antonio'),  -- DANE 47161
  ('co-mag-chivolo',                      'co-mag', 'Chivolo'),  -- DANE 47170
  ('co-mag-cienaga',                      'co-mag', 'Ciénaga'),  -- DANE 47189
  ('co-mag-concordia',                    'co-mag', 'Concordia'),  -- DANE 47205
  ('co-mag-el-banco',                     'co-mag', 'El Banco'),  -- DANE 47245
  ('co-mag-el-pinon',                     'co-mag', 'El Piñón'),  -- DANE 47258
  ('co-mag-el-reten',                     'co-mag', 'El Retén'),  -- DANE 47268
  ('co-mag-fundacion',                    'co-mag', 'Fundación'),  -- DANE 47288
  ('co-mag-guamal',                       'co-mag', 'Guamal'),  -- DANE 47318
  ('co-mag-nueva-granada',                'co-mag', 'Nueva Granada'),  -- DANE 47460
  ('co-mag-pedraza',                      'co-mag', 'Pedraza'),  -- DANE 47541
  ('co-mag-pijino-del-carmen',            'co-mag', 'Pijiño del Carmen'),  -- DANE 47545
  ('co-mag-pivijay',                      'co-mag', 'Pivijay'),  -- DANE 47551
  ('co-mag-plato',                        'co-mag', 'Plato'),  -- DANE 47555
  ('co-mag-puebloviejo',                  'co-mag', 'Puebloviejo'),  -- DANE 47570
  ('co-mag-remolino',                     'co-mag', 'Remolino'),  -- DANE 47605
  ('co-mag-sabanas-de-san-angel',         'co-mag', 'Sabanas de San Ángel'),  -- DANE 47660
  ('co-mag-salamina',                     'co-mag', 'Salamina'),  -- DANE 47675
  ('co-mag-san-sebastian-de-buenavista',  'co-mag', 'San Sebastián de Buenavista'),  -- DANE 47692
  ('co-mag-san-zenon',                    'co-mag', 'San Zenón'),  -- DANE 47703
  ('co-mag-santa-ana',                    'co-mag', 'Santa Ana'),  -- DANE 47707
  ('co-mag-santa-barbara-de-pinto',       'co-mag', 'Santa Bárbara de Pinto'),  -- DANE 47720
  ('co-mag-sitionuevo',                   'co-mag', 'Sitionuevo'),  -- DANE 47745
  ('co-mag-tenerife',                     'co-mag', 'Tenerife'),  -- DANE 47798
  ('co-mag-zapayan',                      'co-mag', 'Zapayán'),  -- DANE 47960
  ('co-mag-zona-bananera',                'co-mag', 'Zona Bananera')  -- DANE 47980
ON CONFLICT (id) DO NOTHING;

-- MET · Meta (DANE 50) — 29 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-met-villavicencio',         'co-met', 'Villavicencio'),  -- DANE 50001
  ('co-met-acacias',               'co-met', 'Acacías'),  -- DANE 50006
  ('co-met-barranca-de-upia',      'co-met', 'Barranca de Upía'),  -- DANE 50110
  ('co-met-cabuyaro',              'co-met', 'Cabuyaro'),  -- DANE 50124
  ('co-met-castilla-la-nueva',     'co-met', 'Castilla la Nueva'),  -- DANE 50150
  ('co-met-cubarral',              'co-met', 'Cubarral'),  -- DANE 50223
  ('co-met-cumaral',               'co-met', 'Cumaral'),  -- DANE 50226
  ('co-met-el-calvario',           'co-met', 'El Calvario'),  -- DANE 50245
  ('co-met-el-castillo',           'co-met', 'El Castillo'),  -- DANE 50251
  ('co-met-el-dorado',             'co-met', 'El Dorado'),  -- DANE 50270
  ('co-met-fuente-de-oro',         'co-met', 'Fuente de Oro'),  -- DANE 50287
  ('co-met-granada',               'co-met', 'Granada'),  -- DANE 50313
  ('co-met-guamal',                'co-met', 'Guamal'),  -- DANE 50318
  ('co-met-mapiripan',             'co-met', 'Mapiripán'),  -- DANE 50325
  ('co-met-mesetas',               'co-met', 'Mesetas'),  -- DANE 50330
  ('co-met-la-macarena',           'co-met', 'La Macarena'),  -- DANE 50350
  ('co-met-uribe',                 'co-met', 'Uribe'),  -- DANE 50370
  ('co-met-lejanias',              'co-met', 'Lejanías'),  -- DANE 50400
  ('co-met-puerto-concordia',      'co-met', 'Puerto Concordia'),  -- DANE 50450
  ('co-met-puerto-gaitan',         'co-met', 'Puerto Gaitán'),  -- DANE 50568
  ('co-met-puerto-lopez',          'co-met', 'Puerto López'),  -- DANE 50573
  ('co-met-puerto-lleras',         'co-met', 'Puerto Lleras'),  -- DANE 50577
  ('co-met-puerto-rico',           'co-met', 'Puerto Rico'),  -- DANE 50590
  ('co-met-restrepo',              'co-met', 'Restrepo'),  -- DANE 50606
  ('co-met-san-carlos-de-guaroa',  'co-met', 'San Carlos de Guaroa'),  -- DANE 50680
  ('co-met-san-juan-de-arama',     'co-met', 'San Juan de Arama'),  -- DANE 50683
  ('co-met-san-juanito',           'co-met', 'San Juanito'),  -- DANE 50686
  ('co-met-san-martin',            'co-met', 'San Martín'),  -- DANE 50689
  ('co-met-vistahermosa',          'co-met', 'Vistahermosa')  -- DANE 50711
ON CONFLICT (id) DO NOTHING;

-- NAR · Nariño (DANE 52) — 64 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-nar-pasto',                 'co-nar', 'Pasto'),  -- DANE 52001
  ('co-nar-alban',                 'co-nar', 'Albán'),  -- DANE 52019
  ('co-nar-aldana',                'co-nar', 'Aldana'),  -- DANE 52022
  ('co-nar-ancuya',                'co-nar', 'Ancuya'),  -- DANE 52036
  ('co-nar-arboleda',              'co-nar', 'Arboleda'),  -- DANE 52051
  ('co-nar-barbacoas',             'co-nar', 'Barbacoas'),  -- DANE 52079
  ('co-nar-belen',                 'co-nar', 'Belén'),  -- DANE 52083
  ('co-nar-buesaco',               'co-nar', 'Buesaco'),  -- DANE 52110
  ('co-nar-colon',                 'co-nar', 'Colón'),  -- DANE 52203
  ('co-nar-consaca',               'co-nar', 'Consacá'),  -- DANE 52207
  ('co-nar-contadero',             'co-nar', 'Contadero'),  -- DANE 52210
  ('co-nar-cordoba',               'co-nar', 'Córdoba'),  -- DANE 52215
  ('co-nar-cuaspud-carlosama',     'co-nar', 'Cuaspud Carlosama'),  -- DANE 52224
  ('co-nar-cumbal',                'co-nar', 'Cumbal'),  -- DANE 52227
  ('co-nar-cumbitara',             'co-nar', 'Cumbitara'),  -- DANE 52233
  ('co-nar-chachagui',             'co-nar', 'Chachagüí'),  -- DANE 52240
  ('co-nar-el-charco',             'co-nar', 'El Charco'),  -- DANE 52250
  ('co-nar-el-penol',              'co-nar', 'El Peñol'),  -- DANE 52254
  ('co-nar-el-rosario',            'co-nar', 'El Rosario'),  -- DANE 52256
  ('co-nar-el-tablon-de-gomez',    'co-nar', 'El Tablón de Gómez'),  -- DANE 52258
  ('co-nar-el-tambo',              'co-nar', 'El Tambo'),  -- DANE 52260
  ('co-nar-funes',                 'co-nar', 'Funes'),  -- DANE 52287
  ('co-nar-guachucal',             'co-nar', 'Guachucal'),  -- DANE 52317
  ('co-nar-guaitarilla',           'co-nar', 'Guaitarilla'),  -- DANE 52320
  ('co-nar-gualmatan',             'co-nar', 'Gualmatán'),  -- DANE 52323
  ('co-nar-iles',                  'co-nar', 'Iles'),  -- DANE 52352
  ('co-nar-imues',                 'co-nar', 'Imués'),  -- DANE 52354
  ('co-nar-ipiales',               'co-nar', 'Ipiales'),  -- DANE 52356
  ('co-nar-la-cruz',               'co-nar', 'La Cruz'),  -- DANE 52378
  ('co-nar-la-florida',            'co-nar', 'La Florida'),  -- DANE 52381
  ('co-nar-la-llanada',            'co-nar', 'La Llanada'),  -- DANE 52385
  ('co-nar-la-tola',               'co-nar', 'La Tola'),  -- DANE 52390
  ('co-nar-la-union',              'co-nar', 'La Unión'),  -- DANE 52399
  ('co-nar-leiva',                 'co-nar', 'Leiva'),  -- DANE 52405
  ('co-nar-linares',               'co-nar', 'Linares'),  -- DANE 52411
  ('co-nar-los-andes',             'co-nar', 'Los Andes'),  -- DANE 52418
  ('co-nar-magui',                 'co-nar', 'Magüí'),  -- DANE 52427
  ('co-nar-mallama',               'co-nar', 'Mallama'),  -- DANE 52435
  ('co-nar-mosquera',              'co-nar', 'Mosquera'),  -- DANE 52473
  ('co-nar-narino',                'co-nar', 'Nariño'),  -- DANE 52480
  ('co-nar-olaya-herrera',         'co-nar', 'Olaya Herrera'),  -- DANE 52490
  ('co-nar-ospina',                'co-nar', 'Ospina'),  -- DANE 52506
  ('co-nar-francisco-pizarro',     'co-nar', 'Francisco Pizarro'),  -- DANE 52520
  ('co-nar-policarpa',             'co-nar', 'Policarpa'),  -- DANE 52540
  ('co-nar-potosi',                'co-nar', 'Potosí'),  -- DANE 52560
  ('co-nar-providencia',           'co-nar', 'Providencia'),  -- DANE 52565
  ('co-nar-puerres',               'co-nar', 'Puerres'),  -- DANE 52573
  ('co-nar-pupiales',              'co-nar', 'Pupiales'),  -- DANE 52585
  ('co-nar-ricaurte',              'co-nar', 'Ricaurte'),  -- DANE 52612
  ('co-nar-roberto-payan',         'co-nar', 'Roberto Payán'),  -- DANE 52621
  ('co-nar-samaniego',             'co-nar', 'Samaniego'),  -- DANE 52678
  ('co-nar-sandona',               'co-nar', 'Sandoná'),  -- DANE 52683
  ('co-nar-san-bernardo',          'co-nar', 'San Bernardo'),  -- DANE 52685
  ('co-nar-san-lorenzo',           'co-nar', 'San Lorenzo'),  -- DANE 52687
  ('co-nar-san-pablo',             'co-nar', 'San Pablo'),  -- DANE 52693
  ('co-nar-san-pedro-de-cartago',  'co-nar', 'San Pedro de Cartago'),  -- DANE 52694
  ('co-nar-santa-barbara',         'co-nar', 'Santa Bárbara'),  -- DANE 52696
  ('co-nar-santacruz',             'co-nar', 'Santacruz'),  -- DANE 52699
  ('co-nar-sapuyes',               'co-nar', 'Sapuyes'),  -- DANE 52720
  ('co-nar-taminango',             'co-nar', 'Taminango'),  -- DANE 52786
  ('co-nar-tangua',                'co-nar', 'Tangua'),  -- DANE 52788
  ('co-nar-san-andres-de-tumaco',  'co-nar', 'San Andrés de Tumaco'),  -- DANE 52835
  ('co-nar-tuquerres',             'co-nar', 'Túquerres'),  -- DANE 52838
  ('co-nar-yacuanquer',            'co-nar', 'Yacuanquer')  -- DANE 52885
ON CONFLICT (id) DO NOTHING;

-- NSA · Norte de Santander (DANE 54) — 40 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-nsa-san-jose-de-cucuta',  'co-nsa', 'San José de Cúcuta'),  -- DANE 54001
  ('co-nsa-abrego',              'co-nsa', 'Ábrego'),  -- DANE 54003
  ('co-nsa-arboledas',           'co-nsa', 'Arboledas'),  -- DANE 54051
  ('co-nsa-bochalema',           'co-nsa', 'Bochalema'),  -- DANE 54099
  ('co-nsa-bucarasica',          'co-nsa', 'Bucarasica'),  -- DANE 54109
  ('co-nsa-cacota',              'co-nsa', 'Cácota'),  -- DANE 54125
  ('co-nsa-cachira',             'co-nsa', 'Cáchira'),  -- DANE 54128
  ('co-nsa-chinacota',           'co-nsa', 'Chinácota'),  -- DANE 54172
  ('co-nsa-chitaga',             'co-nsa', 'Chitagá'),  -- DANE 54174
  ('co-nsa-convencion',          'co-nsa', 'Convención'),  -- DANE 54206
  ('co-nsa-cucutilla',           'co-nsa', 'Cucutilla'),  -- DANE 54223
  ('co-nsa-durania',             'co-nsa', 'Durania'),  -- DANE 54239
  ('co-nsa-el-carmen',           'co-nsa', 'El Carmen'),  -- DANE 54245
  ('co-nsa-el-tarra',            'co-nsa', 'El Tarra'),  -- DANE 54250
  ('co-nsa-el-zulia',            'co-nsa', 'El Zulia'),  -- DANE 54261
  ('co-nsa-gramalote',           'co-nsa', 'Gramalote'),  -- DANE 54313
  ('co-nsa-hacari',              'co-nsa', 'Hacarí'),  -- DANE 54344
  ('co-nsa-herran',              'co-nsa', 'Herrán'),  -- DANE 54347
  ('co-nsa-labateca',            'co-nsa', 'Labateca'),  -- DANE 54377
  ('co-nsa-la-esperanza',        'co-nsa', 'La Esperanza'),  -- DANE 54385
  ('co-nsa-la-playa',            'co-nsa', 'La Playa'),  -- DANE 54398
  ('co-nsa-los-patios',          'co-nsa', 'Los Patios'),  -- DANE 54405
  ('co-nsa-lourdes',             'co-nsa', 'Lourdes'),  -- DANE 54418
  ('co-nsa-mutiscua',            'co-nsa', 'Mutiscua'),  -- DANE 54480
  ('co-nsa-ocana',               'co-nsa', 'Ocaña'),  -- DANE 54498
  ('co-nsa-pamplona',            'co-nsa', 'Pamplona'),  -- DANE 54518
  ('co-nsa-pamplonita',          'co-nsa', 'Pamplonita'),  -- DANE 54520
  ('co-nsa-puerto-santander',    'co-nsa', 'Puerto Santander'),  -- DANE 54553
  ('co-nsa-ragonvalia',          'co-nsa', 'Ragonvalia'),  -- DANE 54599
  ('co-nsa-salazar',             'co-nsa', 'Salazar'),  -- DANE 54660
  ('co-nsa-san-calixto',         'co-nsa', 'San Calixto'),  -- DANE 54670
  ('co-nsa-san-cayetano',        'co-nsa', 'San Cayetano'),  -- DANE 54673
  ('co-nsa-santiago',            'co-nsa', 'Santiago'),  -- DANE 54680
  ('co-nsa-sardinata',           'co-nsa', 'Sardinata'),  -- DANE 54720
  ('co-nsa-silos',               'co-nsa', 'Silos'),  -- DANE 54743
  ('co-nsa-teorama',             'co-nsa', 'Teorama'),  -- DANE 54800
  ('co-nsa-tibu',                'co-nsa', 'Tibú'),  -- DANE 54810
  ('co-nsa-toledo',              'co-nsa', 'Toledo'),  -- DANE 54820
  ('co-nsa-villa-caro',          'co-nsa', 'Villa Caro'),  -- DANE 54871
  ('co-nsa-villa-del-rosario',   'co-nsa', 'Villa del Rosario')  -- DANE 54874
ON CONFLICT (id) DO NOTHING;

-- QUI · Quindío (DANE 63) — 12 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-qui-armenia',     'co-qui', 'Armenia'),  -- DANE 63001
  ('co-qui-buenavista',  'co-qui', 'Buenavista'),  -- DANE 63111
  ('co-qui-calarca',     'co-qui', 'Calarcá'),  -- DANE 63130
  ('co-qui-circasia',    'co-qui', 'Circasia'),  -- DANE 63190
  ('co-qui-cordoba',     'co-qui', 'Córdoba'),  -- DANE 63212
  ('co-qui-filandia',    'co-qui', 'Filandia'),  -- DANE 63272
  ('co-qui-genova',      'co-qui', 'Génova'),  -- DANE 63302
  ('co-qui-la-tebaida',  'co-qui', 'La Tebaida'),  -- DANE 63401
  ('co-qui-montenegro',  'co-qui', 'Montenegro'),  -- DANE 63470
  ('co-qui-pijao',       'co-qui', 'Pijao'),  -- DANE 63548
  ('co-qui-quimbaya',    'co-qui', 'Quimbaya'),  -- DANE 63594
  ('co-qui-salento',     'co-qui', 'Salento')  -- DANE 63690
ON CONFLICT (id) DO NOTHING;

-- RIS · Risaralda (DANE 66) — 14 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-ris-pereira',              'co-ris', 'Pereira'),  -- DANE 66001
  ('co-ris-apia',                 'co-ris', 'Apía'),  -- DANE 66045
  ('co-ris-balboa',               'co-ris', 'Balboa'),  -- DANE 66075
  ('co-ris-belen-de-umbria',      'co-ris', 'Belén de Umbría'),  -- DANE 66088
  ('co-ris-dosquebradas',         'co-ris', 'Dosquebradas'),  -- DANE 66170
  ('co-ris-guatica',              'co-ris', 'Guática'),  -- DANE 66318
  ('co-ris-la-celia',             'co-ris', 'La Celia'),  -- DANE 66383
  ('co-ris-la-virginia',          'co-ris', 'La Virginia'),  -- DANE 66400
  ('co-ris-marsella',             'co-ris', 'Marsella'),  -- DANE 66440
  ('co-ris-mistrato',             'co-ris', 'Mistrató'),  -- DANE 66456
  ('co-ris-pueblo-rico',          'co-ris', 'Pueblo Rico'),  -- DANE 66572
  ('co-ris-quinchia',             'co-ris', 'Quinchía'),  -- DANE 66594
  ('co-ris-santa-rosa-de-cabal',  'co-ris', 'Santa Rosa de Cabal'),  -- DANE 66682
  ('co-ris-santuario',            'co-ris', 'Santuario')  -- DANE 66687
ON CONFLICT (id) DO NOTHING;

-- SAN · Santander (DANE 68) — 87 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-san-bucaramanga',             'co-san', 'Bucaramanga'),  -- DANE 68001
  ('co-san-aguada',                  'co-san', 'Aguada'),  -- DANE 68013
  ('co-san-albania',                 'co-san', 'Albania'),  -- DANE 68020
  ('co-san-aratoca',                 'co-san', 'Aratoca'),  -- DANE 68051
  ('co-san-barbosa',                 'co-san', 'Barbosa'),  -- DANE 68077
  ('co-san-barichara',               'co-san', 'Barichara'),  -- DANE 68079
  ('co-san-barrancabermeja',         'co-san', 'Barrancabermeja'),  -- DANE 68081
  ('co-san-betulia',                 'co-san', 'Betulia'),  -- DANE 68092
  ('co-san-bolivar',                 'co-san', 'Bolívar'),  -- DANE 68101
  ('co-san-cabrera',                 'co-san', 'Cabrera'),  -- DANE 68121
  ('co-san-california',              'co-san', 'California'),  -- DANE 68132
  ('co-san-capitanejo',              'co-san', 'Capitanejo'),  -- DANE 68147
  ('co-san-carcasi',                 'co-san', 'Carcasí'),  -- DANE 68152
  ('co-san-cepita',                  'co-san', 'Cepitá'),  -- DANE 68160
  ('co-san-cerrito',                 'co-san', 'Cerrito'),  -- DANE 68162
  ('co-san-charala',                 'co-san', 'Charalá'),  -- DANE 68167
  ('co-san-charta',                  'co-san', 'Charta'),  -- DANE 68169
  ('co-san-chima',                   'co-san', 'Chima'),  -- DANE 68176
  ('co-san-chipata',                 'co-san', 'Chipatá'),  -- DANE 68179
  ('co-san-cimitarra',               'co-san', 'Cimitarra'),  -- DANE 68190
  ('co-san-concepcion',              'co-san', 'Concepción'),  -- DANE 68207
  ('co-san-confines',                'co-san', 'Confines'),  -- DANE 68209
  ('co-san-contratacion',            'co-san', 'Contratación'),  -- DANE 68211
  ('co-san-coromoro',                'co-san', 'Coromoro'),  -- DANE 68217
  ('co-san-curiti',                  'co-san', 'Curití'),  -- DANE 68229
  ('co-san-el-carmen-de-chucuri',    'co-san', 'El Carmen de Chucurí'),  -- DANE 68235
  ('co-san-el-guacamayo',            'co-san', 'El Guacamayo'),  -- DANE 68245
  ('co-san-el-penon',                'co-san', 'El Peñón'),  -- DANE 68250
  ('co-san-el-playon',               'co-san', 'El Playón'),  -- DANE 68255
  ('co-san-encino',                  'co-san', 'Encino'),  -- DANE 68264
  ('co-san-enciso',                  'co-san', 'Enciso'),  -- DANE 68266
  ('co-san-florian',                 'co-san', 'Florián'),  -- DANE 68271
  ('co-san-floridablanca',           'co-san', 'Floridablanca'),  -- DANE 68276
  ('co-san-galan',                   'co-san', 'Galán'),  -- DANE 68296
  ('co-san-gambita',                 'co-san', 'Gámbita'),  -- DANE 68298
  ('co-san-giron',                   'co-san', 'Girón'),  -- DANE 68307
  ('co-san-guaca',                   'co-san', 'Guaca'),  -- DANE 68318
  ('co-san-guadalupe',               'co-san', 'Guadalupe'),  -- DANE 68320
  ('co-san-guapota',                 'co-san', 'Guapotá'),  -- DANE 68322
  ('co-san-guavata',                 'co-san', 'Guavatá'),  -- DANE 68324
  ('co-san-guepsa',                  'co-san', 'Güepsa'),  -- DANE 68327
  ('co-san-hato',                    'co-san', 'Hato'),  -- DANE 68344
  ('co-san-jesus-maria',             'co-san', 'Jesús María'),  -- DANE 68368
  ('co-san-jordan',                  'co-san', 'Jordán'),  -- DANE 68370
  ('co-san-la-belleza',              'co-san', 'La Belleza'),  -- DANE 68377
  ('co-san-landazuri',               'co-san', 'Landázuri'),  -- DANE 68385
  ('co-san-la-paz',                  'co-san', 'La Paz'),  -- DANE 68397
  ('co-san-lebrija',                 'co-san', 'Lebrija'),  -- DANE 68406
  ('co-san-los-santos',              'co-san', 'Los Santos'),  -- DANE 68418
  ('co-san-macaravita',              'co-san', 'Macaravita'),  -- DANE 68425
  ('co-san-malaga',                  'co-san', 'Málaga'),  -- DANE 68432
  ('co-san-matanza',                 'co-san', 'Matanza'),  -- DANE 68444
  ('co-san-mogotes',                 'co-san', 'Mogotes'),  -- DANE 68464
  ('co-san-molagavita',              'co-san', 'Molagavita'),  -- DANE 68468
  ('co-san-ocamonte',                'co-san', 'Ocamonte'),  -- DANE 68498
  ('co-san-oiba',                    'co-san', 'Oiba'),  -- DANE 68500
  ('co-san-onzaga',                  'co-san', 'Onzaga'),  -- DANE 68502
  ('co-san-palmar',                  'co-san', 'Palmar'),  -- DANE 68522
  ('co-san-palmas-del-socorro',      'co-san', 'Palmas del Socorro'),  -- DANE 68524
  ('co-san-paramo',                  'co-san', 'Páramo'),  -- DANE 68533
  ('co-san-piedecuesta',             'co-san', 'Piedecuesta'),  -- DANE 68547
  ('co-san-pinchote',                'co-san', 'Pinchote'),  -- DANE 68549
  ('co-san-puente-nacional',         'co-san', 'Puente Nacional'),  -- DANE 68572
  ('co-san-puerto-parra',            'co-san', 'Puerto Parra'),  -- DANE 68573
  ('co-san-puerto-wilches',          'co-san', 'Puerto Wilches'),  -- DANE 68575
  ('co-san-rionegro',                'co-san', 'Rionegro'),  -- DANE 68615
  ('co-san-sabana-de-torres',        'co-san', 'Sabana de Torres'),  -- DANE 68655
  ('co-san-san-andres',              'co-san', 'San Andrés'),  -- DANE 68669
  ('co-san-san-benito',              'co-san', 'San Benito'),  -- DANE 68673
  ('co-san-san-gil',                 'co-san', 'San Gil'),  -- DANE 68679
  ('co-san-san-joaquin',             'co-san', 'San Joaquín'),  -- DANE 68682
  ('co-san-san-jose-de-miranda',     'co-san', 'San José de Miranda'),  -- DANE 68684
  ('co-san-san-miguel',              'co-san', 'San Miguel'),  -- DANE 68686
  ('co-san-san-vicente-de-chucuri',  'co-san', 'San Vicente de Chucurí'),  -- DANE 68689
  ('co-san-santa-barbara',           'co-san', 'Santa Bárbara'),  -- DANE 68705
  ('co-san-santa-helena-del-opon',   'co-san', 'Santa Helena del Opón'),  -- DANE 68720
  ('co-san-simacota',                'co-san', 'Simacota'),  -- DANE 68745
  ('co-san-socorro',                 'co-san', 'Socorro'),  -- DANE 68755
  ('co-san-suaita',                  'co-san', 'Suaita'),  -- DANE 68770
  ('co-san-sucre',                   'co-san', 'Sucre'),  -- DANE 68773
  ('co-san-surata',                  'co-san', 'Suratá'),  -- DANE 68780
  ('co-san-tona',                    'co-san', 'Tona'),  -- DANE 68820
  ('co-san-valle-de-san-jose',       'co-san', 'Valle de San José'),  -- DANE 68855
  ('co-san-velez',                   'co-san', 'Vélez'),  -- DANE 68861
  ('co-san-vetas',                   'co-san', 'Vetas'),  -- DANE 68867
  ('co-san-villanueva',              'co-san', 'Villanueva'),  -- DANE 68872
  ('co-san-zapatoca',                'co-san', 'Zapatoca')  -- DANE 68895
ON CONFLICT (id) DO NOTHING;

-- SUC · Sucre (DANE 70) — 26 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-suc-sincelejo',              'co-suc', 'Sincelejo'),  -- DANE 70001
  ('co-suc-buenavista',             'co-suc', 'Buenavista'),  -- DANE 70110
  ('co-suc-caimito',                'co-suc', 'Caimito'),  -- DANE 70124
  ('co-suc-coloso',                 'co-suc', 'Colosó'),  -- DANE 70204
  ('co-suc-corozal',                'co-suc', 'Corozal'),  -- DANE 70215
  ('co-suc-covenas',                'co-suc', 'Coveñas'),  -- DANE 70221
  ('co-suc-chalan',                 'co-suc', 'Chalán'),  -- DANE 70230
  ('co-suc-el-roble',               'co-suc', 'El Roble'),  -- DANE 70233
  ('co-suc-galeras',                'co-suc', 'Galeras'),  -- DANE 70235
  ('co-suc-guaranda',               'co-suc', 'Guaranda'),  -- DANE 70265
  ('co-suc-la-union',               'co-suc', 'La Unión'),  -- DANE 70400
  ('co-suc-los-palmitos',           'co-suc', 'Los Palmitos'),  -- DANE 70418
  ('co-suc-majagual',               'co-suc', 'Majagual'),  -- DANE 70429
  ('co-suc-morroa',                 'co-suc', 'Morroa'),  -- DANE 70473
  ('co-suc-ovejas',                 'co-suc', 'Ovejas'),  -- DANE 70508
  ('co-suc-palmito',                'co-suc', 'Palmito'),  -- DANE 70523
  ('co-suc-sampues',                'co-suc', 'Sampués'),  -- DANE 70670
  ('co-suc-san-benito-abad',        'co-suc', 'San Benito Abad'),  -- DANE 70678
  ('co-suc-san-juan-de-betulia',    'co-suc', 'San Juan de Betulia'),  -- DANE 70702
  ('co-suc-san-marcos',             'co-suc', 'San Marcos'),  -- DANE 70708
  ('co-suc-san-onofre',             'co-suc', 'San Onofre'),  -- DANE 70713
  ('co-suc-san-pedro',              'co-suc', 'San Pedro'),  -- DANE 70717
  ('co-suc-san-luis-de-since',      'co-suc', 'San Luis de Sincé'),  -- DANE 70742
  ('co-suc-sucre',                  'co-suc', 'Sucre'),  -- DANE 70771
  ('co-suc-santiago-de-tolu',       'co-suc', 'Santiago de Tolú'),  -- DANE 70820
  ('co-suc-san-jose-de-toluviejo',  'co-suc', 'San José de Toluviejo')  -- DANE 70823
ON CONFLICT (id) DO NOTHING;

-- TOL · Tolima (DANE 73) — 47 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-tol-ibague',                      'co-tol', 'Ibagué'),  -- DANE 73001
  ('co-tol-alpujarra',                   'co-tol', 'Alpujarra'),  -- DANE 73024
  ('co-tol-alvarado',                    'co-tol', 'Alvarado'),  -- DANE 73026
  ('co-tol-ambalema',                    'co-tol', 'Ambalema'),  -- DANE 73030
  ('co-tol-anzoategui',                  'co-tol', 'Anzoátegui'),  -- DANE 73043
  ('co-tol-armero',                      'co-tol', 'Armero'),  -- DANE 73055
  ('co-tol-ataco',                       'co-tol', 'Ataco'),  -- DANE 73067
  ('co-tol-cajamarca',                   'co-tol', 'Cajamarca'),  -- DANE 73124
  ('co-tol-carmen-de-apicala',           'co-tol', 'Carmen de Apicalá'),  -- DANE 73148
  ('co-tol-casabianca',                  'co-tol', 'Casabianca'),  -- DANE 73152
  ('co-tol-chaparral',                   'co-tol', 'Chaparral'),  -- DANE 73168
  ('co-tol-coello',                      'co-tol', 'Coello'),  -- DANE 73200
  ('co-tol-coyaima',                     'co-tol', 'Coyaima'),  -- DANE 73217
  ('co-tol-cunday',                      'co-tol', 'Cunday'),  -- DANE 73226
  ('co-tol-dolores',                     'co-tol', 'Dolores'),  -- DANE 73236
  ('co-tol-espinal',                     'co-tol', 'Espinal'),  -- DANE 73268
  ('co-tol-falan',                       'co-tol', 'Falan'),  -- DANE 73270
  ('co-tol-flandes',                     'co-tol', 'Flandes'),  -- DANE 73275
  ('co-tol-fresno',                      'co-tol', 'Fresno'),  -- DANE 73283
  ('co-tol-guamo',                       'co-tol', 'Guamo'),  -- DANE 73319
  ('co-tol-herveo',                      'co-tol', 'Herveo'),  -- DANE 73347
  ('co-tol-honda',                       'co-tol', 'Honda'),  -- DANE 73349
  ('co-tol-icononzo',                    'co-tol', 'Icononzo'),  -- DANE 73352
  ('co-tol-lerida',                      'co-tol', 'Lérida'),  -- DANE 73408
  ('co-tol-libano',                      'co-tol', 'Líbano'),  -- DANE 73411
  ('co-tol-san-sebastian-de-mariquita',  'co-tol', 'San Sebastián de Mariquita'),  -- DANE 73443
  ('co-tol-melgar',                      'co-tol', 'Melgar'),  -- DANE 73449
  ('co-tol-murillo',                     'co-tol', 'Murillo'),  -- DANE 73461
  ('co-tol-natagaima',                   'co-tol', 'Natagaima'),  -- DANE 73483
  ('co-tol-ortega',                      'co-tol', 'Ortega'),  -- DANE 73504
  ('co-tol-palocabildo',                 'co-tol', 'Palocabildo'),  -- DANE 73520
  ('co-tol-piedras',                     'co-tol', 'Piedras'),  -- DANE 73547
  ('co-tol-planadas',                    'co-tol', 'Planadas'),  -- DANE 73555
  ('co-tol-prado',                       'co-tol', 'Prado'),  -- DANE 73563
  ('co-tol-purificacion',                'co-tol', 'Purificación'),  -- DANE 73585
  ('co-tol-rioblanco',                   'co-tol', 'Rioblanco'),  -- DANE 73616
  ('co-tol-roncesvalles',                'co-tol', 'Roncesvalles'),  -- DANE 73622
  ('co-tol-rovira',                      'co-tol', 'Rovira'),  -- DANE 73624
  ('co-tol-saldana',                     'co-tol', 'Saldaña'),  -- DANE 73671
  ('co-tol-san-antonio',                 'co-tol', 'San Antonio'),  -- DANE 73675
  ('co-tol-san-luis',                    'co-tol', 'San Luis'),  -- DANE 73678
  ('co-tol-santa-isabel',                'co-tol', 'Santa Isabel'),  -- DANE 73686
  ('co-tol-suarez',                      'co-tol', 'Suárez'),  -- DANE 73770
  ('co-tol-valle-de-san-juan',           'co-tol', 'Valle de San Juan'),  -- DANE 73854
  ('co-tol-venadillo',                   'co-tol', 'Venadillo'),  -- DANE 73861
  ('co-tol-villahermosa',                'co-tol', 'Villahermosa'),  -- DANE 73870
  ('co-tol-villarrica',                  'co-tol', 'Villarrica')  -- DANE 73873
ON CONFLICT (id) DO NOTHING;

-- VAC · Valle del Cauca (DANE 76) — 42 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-vac-santiago-de-cali',     'co-vac', 'Santiago de Cali'),  -- DANE 76001
  ('co-vac-alcala',               'co-vac', 'Alcalá'),  -- DANE 76020
  ('co-vac-andalucia',            'co-vac', 'Andalucía'),  -- DANE 76036
  ('co-vac-ansermanuevo',         'co-vac', 'Ansermanuevo'),  -- DANE 76041
  ('co-vac-argelia',              'co-vac', 'Argelia'),  -- DANE 76054
  ('co-vac-bolivar',              'co-vac', 'Bolívar'),  -- DANE 76100
  ('co-vac-buenaventura',         'co-vac', 'Buenaventura'),  -- DANE 76109
  ('co-vac-guadalajara-de-buga',  'co-vac', 'Guadalajara de Buga'),  -- DANE 76111
  ('co-vac-bugalagrande',         'co-vac', 'Bugalagrande'),  -- DANE 76113
  ('co-vac-caicedonia',           'co-vac', 'Caicedonia'),  -- DANE 76122
  ('co-vac-calima',               'co-vac', 'Calima'),  -- DANE 76126
  ('co-vac-candelaria',           'co-vac', 'Candelaria'),  -- DANE 76130
  ('co-vac-cartago',              'co-vac', 'Cartago'),  -- DANE 76147
  ('co-vac-dagua',                'co-vac', 'Dagua'),  -- DANE 76233
  ('co-vac-el-aguila',            'co-vac', 'El Águila'),  -- DANE 76243
  ('co-vac-el-cairo',             'co-vac', 'El Cairo'),  -- DANE 76246
  ('co-vac-el-cerrito',           'co-vac', 'El Cerrito'),  -- DANE 76248
  ('co-vac-el-dovio',             'co-vac', 'El Dovio'),  -- DANE 76250
  ('co-vac-florida',              'co-vac', 'Florida'),  -- DANE 76275
  ('co-vac-ginebra',              'co-vac', 'Ginebra'),  -- DANE 76306
  ('co-vac-guacari',              'co-vac', 'Guacarí'),  -- DANE 76318
  ('co-vac-jamundi',              'co-vac', 'Jamundí'),  -- DANE 76364
  ('co-vac-la-cumbre',            'co-vac', 'La Cumbre'),  -- DANE 76377
  ('co-vac-la-union',             'co-vac', 'La Unión'),  -- DANE 76400
  ('co-vac-la-victoria',          'co-vac', 'La Victoria'),  -- DANE 76403
  ('co-vac-obando',               'co-vac', 'Obando'),  -- DANE 76497
  ('co-vac-palmira',              'co-vac', 'Palmira'),  -- DANE 76520
  ('co-vac-pradera',              'co-vac', 'Pradera'),  -- DANE 76563
  ('co-vac-restrepo',             'co-vac', 'Restrepo'),  -- DANE 76606
  ('co-vac-riofrio',              'co-vac', 'Riofrío'),  -- DANE 76616
  ('co-vac-roldanillo',           'co-vac', 'Roldanillo'),  -- DANE 76622
  ('co-vac-san-pedro',            'co-vac', 'San Pedro'),  -- DANE 76670
  ('co-vac-sevilla',              'co-vac', 'Sevilla'),  -- DANE 76736
  ('co-vac-toro',                 'co-vac', 'Toro'),  -- DANE 76823
  ('co-vac-trujillo',             'co-vac', 'Trujillo'),  -- DANE 76828
  ('co-vac-tulua',                'co-vac', 'Tuluá'),  -- DANE 76834
  ('co-vac-ulloa',                'co-vac', 'Ulloa'),  -- DANE 76845
  ('co-vac-versalles',            'co-vac', 'Versalles'),  -- DANE 76863
  ('co-vac-vijes',                'co-vac', 'Vijes'),  -- DANE 76869
  ('co-vac-yotoco',               'co-vac', 'Yotoco'),  -- DANE 76890
  ('co-vac-yumbo',                'co-vac', 'Yumbo'),  -- DANE 76892
  ('co-vac-zarzal',               'co-vac', 'Zarzal')  -- DANE 76895
ON CONFLICT (id) DO NOTHING;

-- ARA · Arauca (DANE 81) — 7 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-ara-arauca',         'co-ara', 'Arauca'),  -- DANE 81001
  ('co-ara-arauquita',      'co-ara', 'Arauquita'),  -- DANE 81065
  ('co-ara-cravo-norte',    'co-ara', 'Cravo Norte'),  -- DANE 81220
  ('co-ara-fortul',         'co-ara', 'Fortul'),  -- DANE 81300
  ('co-ara-puerto-rondon',  'co-ara', 'Puerto Rondón'),  -- DANE 81591
  ('co-ara-saravena',       'co-ara', 'Saravena'),  -- DANE 81736
  ('co-ara-tame',           'co-ara', 'Tame')  -- DANE 81794
ON CONFLICT (id) DO NOTHING;

-- CAS · Casanare (DANE 85) — 19 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-cas-yopal',                 'co-cas', 'Yopal'),  -- DANE 85001
  ('co-cas-aguazul',               'co-cas', 'Aguazul'),  -- DANE 85010
  ('co-cas-chameza',               'co-cas', 'Chámeza'),  -- DANE 85015
  ('co-cas-hato-corozal',          'co-cas', 'Hato Corozal'),  -- DANE 85125
  ('co-cas-la-salina',             'co-cas', 'La Salina'),  -- DANE 85136
  ('co-cas-mani',                  'co-cas', 'Maní'),  -- DANE 85139
  ('co-cas-monterrey',             'co-cas', 'Monterrey'),  -- DANE 85162
  ('co-cas-nunchia',               'co-cas', 'Nunchía'),  -- DANE 85225
  ('co-cas-orocue',                'co-cas', 'Orocué'),  -- DANE 85230
  ('co-cas-paz-de-ariporo',        'co-cas', 'Paz de Ariporo'),  -- DANE 85250
  ('co-cas-pore',                  'co-cas', 'Pore'),  -- DANE 85263
  ('co-cas-recetor',               'co-cas', 'Recetor'),  -- DANE 85279
  ('co-cas-sabanalarga',           'co-cas', 'Sabanalarga'),  -- DANE 85300
  ('co-cas-sacama',                'co-cas', 'Sácama'),  -- DANE 85315
  ('co-cas-san-luis-de-palenque',  'co-cas', 'San Luis de Palenque'),  -- DANE 85325
  ('co-cas-tamara',                'co-cas', 'Támara'),  -- DANE 85400
  ('co-cas-tauramena',             'co-cas', 'Tauramena'),  -- DANE 85410
  ('co-cas-trinidad',              'co-cas', 'Trinidad'),  -- DANE 85430
  ('co-cas-villanueva',            'co-cas', 'Villanueva')  -- DANE 85440
ON CONFLICT (id) DO NOTHING;

-- PUT · Putumayo (DANE 86) — 13 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-put-mocoa',              'co-put', 'Mocoa'),  -- DANE 86001
  ('co-put-colon',              'co-put', 'Colón'),  -- DANE 86219
  ('co-put-orito',              'co-put', 'Orito'),  -- DANE 86320
  ('co-put-puerto-asis',        'co-put', 'Puerto Asís'),  -- DANE 86568
  ('co-put-puerto-caicedo',     'co-put', 'Puerto Caicedo'),  -- DANE 86569
  ('co-put-puerto-guzman',      'co-put', 'Puerto Guzmán'),  -- DANE 86571
  ('co-put-puerto-leguizamo',   'co-put', 'Puerto Leguízamo'),  -- DANE 86573
  ('co-put-sibundoy',           'co-put', 'Sibundoy'),  -- DANE 86749
  ('co-put-san-francisco',      'co-put', 'San Francisco'),  -- DANE 86755
  ('co-put-san-miguel',         'co-put', 'San Miguel'),  -- DANE 86757
  ('co-put-santiago',           'co-put', 'Santiago'),  -- DANE 86760
  ('co-put-valle-del-guamuez',  'co-put', 'Valle del Guamuez'),  -- DANE 86865
  ('co-put-villagarzon',        'co-put', 'Villagarzón')  -- DANE 86885
ON CONFLICT (id) DO NOTHING;

-- SAP · Archipiélago de San Andrés, Providencia y Santa Catalina (DANE 88) — 2 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-sap-san-andres',   'co-sap', 'San Andrés'),  -- DANE 88001
  ('co-sap-providencia',  'co-sap', 'Providencia')  -- DANE 88564
ON CONFLICT (id) DO NOTHING;

-- AMA · Amazonas (DANE 91) — 2 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-ama-leticia',        'co-ama', 'Leticia'),  -- DANE 91001
  ('co-ama-puerto-narino',  'co-ama', 'Puerto Nariño')  -- DANE 91540
ON CONFLICT (id) DO NOTHING;

-- GUA · Guainía (DANE 94) — 2 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-gua-inirida',        'co-gua', 'Inírida'),  -- DANE 94001
  ('co-gua-barrancominas',  'co-gua', 'Barrancominas')  -- DANE 94343
ON CONFLICT (id) DO NOTHING;

-- GUV · Guaviare (DANE 95) — 4 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-guv-san-jose-del-guaviare',  'co-guv', 'San José del Guaviare'),  -- DANE 95001
  ('co-guv-calamar',                'co-guv', 'Calamar'),  -- DANE 95015
  ('co-guv-el-retorno',             'co-guv', 'El Retorno'),  -- DANE 95025
  ('co-guv-miraflores',             'co-guv', 'Miraflores')  -- DANE 95200
ON CONFLICT (id) DO NOTHING;

-- VAU · Vaupés (DANE 97) — 3 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-vau-mitu',     'co-vau', 'Mitú'),  -- DANE 97001
  ('co-vau-caruru',   'co-vau', 'Carurú'),  -- DANE 97161
  ('co-vau-taraira',  'co-vau', 'Taraira')  -- DANE 97666
ON CONFLICT (id) DO NOTHING;

-- VID · Vichada (DANE 99) — 4 municipios
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-vid-puerto-carreno',  'co-vid', 'Puerto Carreño'),  -- DANE 99001
  ('co-vid-la-primavera',    'co-vid', 'La Primavera'),  -- DANE 99524
  ('co-vid-santa-rosalia',   'co-vid', 'Santa Rosalía'),  -- DANE 99624
  ('co-vid-cumaribo',        'co-vid', 'Cumaribo')  -- DANE 99773
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- =====================================================================================
-- VERIFICACION
--   SELECT count(*) FROM public.municipality;                       -- >= 1104
--   SELECT department_id, count(*) FROM public.municipality
--    GROUP BY department_id ORDER BY department_id;                 -- 33 filas
--   SELECT id, name FROM public.municipality WHERE id IN
--     ('co-atl-barranquilla','co-sap-san-andres','co-dc-bogota');
-- =====================================================================================
