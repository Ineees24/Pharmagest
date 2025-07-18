toc.dat                                                                                             0000600 0004000 0002000 00000131523 15000224312 0014431 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        PGDMP                       }            PharmaGestBD    16.2    16.2 �    h           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                      false         i           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                      false         j           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                      false         k           1262    24920    PharmaGestBD    DATABASE     �   CREATE DATABASE "PharmaGestBD" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'French_France.1252';
    DROP DATABASE "PharmaGestBD";
                postgres    false                     2615    2200    public    SCHEMA        CREATE SCHEMA public;
    DROP SCHEMA public;
                pg_database_owner    false         l           0    0    SCHEMA public    COMMENT     6   COMMENT ON SCHEMA public IS 'standard public schema';
                   pg_database_owner    false    4         �           1247    25194    role    TYPE     E   CREATE TYPE public.role AS ENUM (
    'PHARMACIEN',
    'VENDEUR'
);
    DROP TYPE public.role;
       public          postgres    false    4         l           1247    24928    statutpaiement    TYPE     \   CREATE TYPE public.statutpaiement AS ENUM (
    'EN_ATTENTE',
    'VALIDE',
    'REJETE'
);
 !   DROP TYPE public.statutpaiement;
       public          postgres    false    4         i           1247    24922 	   typevente    TYPE     G   CREATE TYPE public.typevente AS ENUM (
    'LIBRE',
    'PRESCRITE'
);
    DROP TYPE public.typevente;
       public          postgres    false    4                    1255    50512    creer_commande_automatique()    FUNCTION     ]  CREATE FUNCTION public.creer_commande_automatique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
v_fournisseur_id INTEGER;
v_commande_id INTEGER;
v_quantite_a_commander INTEGER;
v_prix_unitaire NUMERIC(10,2);
BEGIN
-- Ne déclencher que si le stock est passé sous le seuil de 10
IF NEW.stock < 10 AND (OLD.stock IS NULL OR OLD.stock >= 10) THEN
    -- Récupérer l'ID du fournisseur associé au médicament
    SELECT fournisseur_id INTO v_fournisseur_id FROM medicament WHERE id = NEW.id;
    
    -- Si pas de fournisseur assigné, utiliser un fournisseur par défaut
    IF v_fournisseur_id IS NULL THEN
        SELECT id INTO v_fournisseur_id FROM fournisseur LIMIT 1;
        
        IF v_fournisseur_id IS NULL THEN
            RAISE EXCEPTION 'Aucun fournisseur disponible pour créer une commande automatique';
            RETURN NEW;
        END IF;
        
        -- Mettre à jour le médicament avec ce fournisseur
        UPDATE medicament SET fournisseur_id = v_fournisseur_id WHERE id = NEW.id;
    END IF;
    
    -- Calculer la quantité à commander (pour atteindre 100)
    v_quantite_a_commander := 100 - NEW.stock;
    
    -- Récupérer le prix d'achat du médicament
    v_prix_unitaire := NEW.prixachat;
    
    -- Vérifier si une commande en attente existe déjà pour ce fournisseur
    SELECT id INTO v_commande_id 
    FROM commande 
    WHERE fournisseur_id = v_fournisseur_id 
      AND statut = 'En attente de confirmation'
    LIMIT 1;
    
    -- Si aucune commande en attente n'existe, en créer une nouvelle
    IF v_commande_id IS NULL THEN
        INSERT INTO commande (montant, fournisseur_id, date_creation, statut)
        VALUES (0, v_fournisseur_id, CURRENT_TIMESTAMP, 'En attente de confirmation')
        RETURNING id INTO v_commande_id;
        
        -- Créer une livraison associée à cette commande avec statut "En cours"
        INSERT INTO livraison (datelivraison, status, commande_id, fournisseur_id)
        VALUES (CURRENT_TIMESTAMP, 'En cours', v_commande_id, v_fournisseur_id);
        
        RAISE NOTICE 'Nouvelle commande créée (ID: %) pour le fournisseur % avec livraison associée', v_commande_id, v_fournisseur_id;
    ELSE
        RAISE NOTICE 'Ajout à une commande existante (ID: %) pour le fournisseur %', v_commande_id, v_fournisseur_id;
    END IF;
    
    -- Vérifier si ce médicament est déjà dans la commande
    IF EXISTS (SELECT 1 FROM lignedecommande WHERE commande_id = v_commande_id AND medicament_id = NEW.id) THEN
        -- Mettre à jour la ligne de commande existante
        UPDATE lignedecommande 
        SET quantitevendu = quantitevendu + v_quantite_a_commander
        WHERE commande_id = v_commande_id AND medicament_id = NEW.id;
        
        RAISE NOTICE 'Mise à jour de la quantité pour le médicament % dans la commande %', NEW.id, v_commande_id;
    ELSE
        -- Ajouter une nouvelle ligne de commande
        INSERT INTO lignedecommande (quantitevendu, prixunitaire, commande_id, medicament_id, quantiterecue, prixachatreel, prixventereel)
        VALUES (v_quantite_a_commander, v_prix_unitaire, v_commande_id, NEW.id, 0, 0, 0);
        
        RAISE NOTICE 'Ajout du médicament % à la commande %', NEW.id, v_commande_id;
    END IF;
    
    -- Mettre à jour le montant total de la commande
    UPDATE commande
    SET montant = (
        SELECT SUM(quantitevendu * prixunitaire)
        FROM lignedecommande
        WHERE commande_id = v_commande_id
    )
    WHERE id = v_commande_id;
    
    RAISE NOTICE 'Commande automatique créée/mise à jour pour le médicament % (stock: %)', NEW.nom, NEW.stock;
END IF;

RETURN NEW;
END;
$$;
 3   DROP FUNCTION public.creer_commande_automatique();
       public          postgres    false    4                    1255    50514    valider_commande(integer)    FUNCTION     W  CREATE FUNCTION public.valider_commande(p_commande_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
r_ligne RECORD;
v_livraison_id INTEGER;
BEGIN
-- Vérifier que la commande existe et est en attente
IF NOT EXISTS (SELECT 1 FROM commande WHERE id = p_commande_id AND statut = 'En attente de confirmation') THEN
    RAISE EXCEPTION 'Commande % inexistante ou déjà validée', p_commande_id;
END IF;

-- Pour chaque ligne de commande, mettre à jour le stock du médicament
FOR r_ligne IN (SELECT medicament_id, quantitevendu FROM lignedecommande WHERE commande_id = p_commande_id) LOOP
    UPDATE medicament
    SET stock = stock + r_ligne.quantitevendu
    WHERE id = r_ligne.medicament_id;
    
    RAISE NOTICE 'Stock du médicament % mis à jour', r_ligne.medicament_id;
END LOOP;

-- Marquer la commande comme validée
UPDATE commande
SET statut = 'Validée'
WHERE id = p_commande_id;

-- Mettre à jour le statut de la livraison associée à "Livrée"
SELECT id INTO v_livraison_id FROM livraison WHERE commande_id = p_commande_id;
IF v_livraison_id IS NOT NULL THEN
    UPDATE livraison
    SET status = 'Livrée'
    WHERE id = v_livraison_id;
    
    RAISE NOTICE 'Livraison % associée à la commande % marquée comme livrée', v_livraison_id, p_commande_id;
END IF;

RAISE NOTICE 'Commande % validée avec succès', p_commande_id;
END;
$$;
 >   DROP FUNCTION public.valider_commande(p_commande_id integer);
       public          postgres    false    4         �            1259    25011    commande    TABLE       CREATE TABLE public.commande (
    id integer NOT NULL,
    montant numeric(10,2) NOT NULL,
    date_creation timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    statut character varying(50) DEFAULT 'En attente de confirmation'::character varying,
    fournisseur_id integer
);
    DROP TABLE public.commande;
       public         heap    postgres    false    4         �            1259    25010    commande_id_seq    SEQUENCE     �   CREATE SEQUENCE public.commande_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.commande_id_seq;
       public          postgres    false    230    4         m           0    0    commande_id_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE public.commande_id_seq OWNED BY public.commande.id;
          public          postgres    false    229         �            1259    25095    facture    TABLE     �   CREATE TABLE public.facture (
    id integer NOT NULL,
    dateemission timestamp without time zone NOT NULL,
    montanttotal numeric(10,2) NOT NULL,
    numerofacture character varying(255) NOT NULL,
    vente_id integer
);
    DROP TABLE public.facture;
       public         heap    postgres    false    4         �            1259    25094    facture_id_seq    SEQUENCE     �   CREATE SEQUENCE public.facture_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE public.facture_id_seq;
       public          postgres    false    4    242         n           0    0    facture_id_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE public.facture_id_seq OWNED BY public.facture.id;
          public          postgres    false    241         �            1259    24936    famille    TABLE     b   CREATE TABLE public.famille (
    id integer NOT NULL,
    nom character varying(255) NOT NULL
);
    DROP TABLE public.famille;
       public         heap    postgres    false    4         �            1259    24935    famille_id_seq    SEQUENCE     �   CREATE SEQUENCE public.famille_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE public.famille_id_seq;
       public          postgres    false    4    216         o           0    0    famille_id_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE public.famille_id_seq OWNED BY public.famille.id;
          public          postgres    false    215         �            1259    24950    fournisseur    TABLE     �   CREATE TABLE public.fournisseur (
    id integer NOT NULL,
    nom character varying(255) NOT NULL,
    adresse character varying(255),
    contact character varying(255),
    email character varying
);
    DROP TABLE public.fournisseur;
       public         heap    postgres    false    4         �            1259    24949    fournisseur_id_seq    SEQUENCE     �   CREATE SEQUENCE public.fournisseur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.fournisseur_id_seq;
       public          postgres    false    220    4         p           0    0    fournisseur_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE public.fournisseur_id_seq OWNED BY public.fournisseur.id;
          public          postgres    false    219         �            1259    25023    lignedecommande    TABLE     =  CREATE TABLE public.lignedecommande (
    id integer NOT NULL,
    quantitevendu integer NOT NULL,
    prixunitaire numeric(10,2) NOT NULL,
    commande_id integer,
    medicament_id integer,
    quantiterecue integer DEFAULT 0,
    prixachatreel numeric(10,2) DEFAULT 0,
    prixventereel numeric(10,2) DEFAULT 0
);
 #   DROP TABLE public.lignedecommande;
       public         heap    postgres    false    4         �            1259    25022    lignedecommande_id_seq    SEQUENCE     �   CREATE SEQUENCE public.lignedecommande_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 -   DROP SEQUENCE public.lignedecommande_id_seq;
       public          postgres    false    232    4         q           0    0    lignedecommande_id_seq    SEQUENCE OWNED BY     Q   ALTER SEQUENCE public.lignedecommande_id_seq OWNED BY public.lignedecommande.id;
          public          postgres    false    231         �            1259    25078 
   lignevente    TABLE     �   CREATE TABLE public.lignevente (
    id integer NOT NULL,
    quantitevendu integer NOT NULL,
    prixunitaire numeric(10,2) NOT NULL,
    vente_id integer,
    medicament_id integer
);
    DROP TABLE public.lignevente;
       public         heap    postgres    false    4         �            1259    25077    lignevente_id_seq    SEQUENCE     �   CREATE SEQUENCE public.lignevente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.lignevente_id_seq;
       public          postgres    false    240    4         r           0    0    lignevente_id_seq    SEQUENCE OWNED BY     G   ALTER SEQUENCE public.lignevente_id_seq OWNED BY public.lignevente.id;
          public          postgres    false    239         �            1259    25119 	   livraison    TABLE     �   CREATE TABLE public.livraison (
    id integer NOT NULL,
    datelivraison timestamp without time zone NOT NULL,
    status character varying(255),
    commande_id integer,
    fournisseur_id integer
);
    DROP TABLE public.livraison;
       public         heap    postgres    false    4         �            1259    25118    livraison_id_seq    SEQUENCE     �   CREATE SEQUENCE public.livraison_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.livraison_id_seq;
       public          postgres    false    246    4         s           0    0    livraison_id_seq    SEQUENCE OWNED BY     E   ALTER SEQUENCE public.livraison_id_seq OWNED BY public.livraison.id;
          public          postgres    false    245         �            1259    24959 
   medicament    TABLE     �  CREATE TABLE public.medicament (
    id integer NOT NULL,
    nom character varying(255) NOT NULL,
    forme character varying(255),
    prixachat numeric(10,2) NOT NULL,
    prixvente numeric(10,2) NOT NULL,
    stock integer NOT NULL,
    seuilcommande integer NOT NULL,
    qtemax integer NOT NULL,
    famille_id integer,
    fournisseur_id integer NOT NULL,
    ordonnance boolean
);
    DROP TABLE public.medicament;
       public         heap    postgres    false    4         �            1259    24958    medicament_id_seq    SEQUENCE     �   CREATE SEQUENCE public.medicament_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.medicament_id_seq;
       public          postgres    false    222    4         t           0    0    medicament_id_seq    SEQUENCE OWNED BY     G   ALTER SEQUENCE public.medicament_id_seq OWNED BY public.medicament.id;
          public          postgres    false    221         �            1259    25107    paiement    TABLE     �   CREATE TABLE public.paiement (
    id integer NOT NULL,
    montant numeric(10,2) NOT NULL,
    modepaiement character varying(255),
    statut public.statutpaiement NOT NULL,
    vente_id integer
);
    DROP TABLE public.paiement;
       public         heap    postgres    false    876    4         �            1259    25106    paiement_id_seq    SEQUENCE     �   CREATE SEQUENCE public.paiement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.paiement_id_seq;
       public          postgres    false    4    244         u           0    0    paiement_id_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE public.paiement_id_seq OWNED BY public.paiement.id;
          public          postgres    false    243         �            1259    25040    patient    TABLE     �   CREATE TABLE public.patient (
    id integer NOT NULL,
    nom character varying(255) NOT NULL,
    prenom character varying(255) NOT NULL,
    datenaissance date NOT NULL,
    adresse character varying(255),
    contact character varying(255)
);
    DROP TABLE public.patient;
       public         heap    postgres    false    4         �            1259    25039    patient_id_seq    SEQUENCE     �   CREATE SEQUENCE public.patient_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE public.patient_id_seq;
       public          postgres    false    4    234         v           0    0    patient_id_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE public.patient_id_seq OWNED BY public.patient.id;
          public          postgres    false    233         �            1259    24987 
   pharmacien    TABLE     X   CREATE TABLE public.pharmacien (
    id integer NOT NULL,
    utilisateur_id integer
);
    DROP TABLE public.pharmacien;
       public         heap    postgres    false    4         �            1259    24986    pharmacien_id_seq    SEQUENCE     �   CREATE SEQUENCE public.pharmacien_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.pharmacien_id_seq;
       public          postgres    false    226    4         w           0    0    pharmacien_id_seq    SEQUENCE OWNED BY     G   ALTER SEQUENCE public.pharmacien_id_seq OWNED BY public.pharmacien.id;
          public          postgres    false    225         �            1259    25049    prescription    TABLE     �   CREATE TABLE public.prescription (
    id integer NOT NULL,
    nommedecin character varying(255) NOT NULL,
    dateprescription timestamp without time zone NOT NULL,
    patient_id integer
);
     DROP TABLE public.prescription;
       public         heap    postgres    false    4         �            1259    25048    prescription_id_seq    SEQUENCE     �   CREATE SEQUENCE public.prescription_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.prescription_id_seq;
       public          postgres    false    4    236         x           0    0    prescription_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.prescription_id_seq OWNED BY public.prescription.id;
          public          postgres    false    235         �            1259    24943    unite    TABLE     e   CREATE TABLE public.unite (
    id integer NOT NULL,
    nomunite character varying(255) NOT NULL
);
    DROP TABLE public.unite;
       public         heap    postgres    false    4         �            1259    24942    unite_id_seq    SEQUENCE     �   CREATE SEQUENCE public.unite_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 #   DROP SEQUENCE public.unite_id_seq;
       public          postgres    false    218    4         y           0    0    unite_id_seq    SEQUENCE OWNED BY     =   ALTER SEQUENCE public.unite_id_seq OWNED BY public.unite.id;
          public          postgres    false    217         �            1259    24978    utilisateur    TABLE     �   CREATE TABLE public.utilisateur (
    id integer NOT NULL,
    identifiant character varying(255) NOT NULL,
    motdepasse character varying(255) NOT NULL,
    role public.role DEFAULT 'PHARMACIEN'::public.role
);
    DROP TABLE public.utilisateur;
       public         heap    postgres    false    927    927    4         �            1259    24977    utilisateur_id_seq    SEQUENCE     �   CREATE SEQUENCE public.utilisateur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.utilisateur_id_seq;
       public          postgres    false    4    224         z           0    0    utilisateur_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE public.utilisateur_id_seq OWNED BY public.utilisateur.id;
          public          postgres    false    223         �            1259    24999    vendeur    TABLE     U   CREATE TABLE public.vendeur (
    id integer NOT NULL,
    utilisateur_id integer
);
    DROP TABLE public.vendeur;
       public         heap    postgres    false    4         �            1259    24998    vendeur_id_seq    SEQUENCE     �   CREATE SEQUENCE public.vendeur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE public.vendeur_id_seq;
       public          postgres    false    4    228         {           0    0    vendeur_id_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE public.vendeur_id_seq OWNED BY public.vendeur.id;
          public          postgres    false    227         �            1259    25061    vente    TABLE     �   CREATE TABLE public.vente (
    id integer NOT NULL,
    datevente timestamp without time zone NOT NULL,
    montanttotal numeric(10,2) NOT NULL,
    typevente public.typevente NOT NULL,
    vendeur_id integer,
    prescription_id integer
);
    DROP TABLE public.vente;
       public         heap    postgres    false    873    4         �            1259    25060    vente_id_seq    SEQUENCE     �   CREATE SEQUENCE public.vente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 #   DROP SEQUENCE public.vente_id_seq;
       public          postgres    false    238    4         |           0    0    vente_id_seq    SEQUENCE OWNED BY     =   ALTER SEQUENCE public.vente_id_seq OWNED BY public.vente.id;
          public          postgres    false    237         x           2604    25014    commande id    DEFAULT     j   ALTER TABLE ONLY public.commande ALTER COLUMN id SET DEFAULT nextval('public.commande_id_seq'::regclass);
 :   ALTER TABLE public.commande ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    230    229    230         �           2604    25098 
   facture id    DEFAULT     h   ALTER TABLE ONLY public.facture ALTER COLUMN id SET DEFAULT nextval('public.facture_id_seq'::regclass);
 9   ALTER TABLE public.facture ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    242    241    242         p           2604    24939 
   famille id    DEFAULT     h   ALTER TABLE ONLY public.famille ALTER COLUMN id SET DEFAULT nextval('public.famille_id_seq'::regclass);
 9   ALTER TABLE public.famille ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    215    216    216         r           2604    24953    fournisseur id    DEFAULT     p   ALTER TABLE ONLY public.fournisseur ALTER COLUMN id SET DEFAULT nextval('public.fournisseur_id_seq'::regclass);
 =   ALTER TABLE public.fournisseur ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    220    219    220         {           2604    25026    lignedecommande id    DEFAULT     x   ALTER TABLE ONLY public.lignedecommande ALTER COLUMN id SET DEFAULT nextval('public.lignedecommande_id_seq'::regclass);
 A   ALTER TABLE public.lignedecommande ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    231    232    232         �           2604    25081    lignevente id    DEFAULT     n   ALTER TABLE ONLY public.lignevente ALTER COLUMN id SET DEFAULT nextval('public.lignevente_id_seq'::regclass);
 <   ALTER TABLE public.lignevente ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    239    240    240         �           2604    25122    livraison id    DEFAULT     l   ALTER TABLE ONLY public.livraison ALTER COLUMN id SET DEFAULT nextval('public.livraison_id_seq'::regclass);
 ;   ALTER TABLE public.livraison ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    245    246    246         s           2604    24962    medicament id    DEFAULT     n   ALTER TABLE ONLY public.medicament ALTER COLUMN id SET DEFAULT nextval('public.medicament_id_seq'::regclass);
 <   ALTER TABLE public.medicament ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    221    222    222         �           2604    25110    paiement id    DEFAULT     j   ALTER TABLE ONLY public.paiement ALTER COLUMN id SET DEFAULT nextval('public.paiement_id_seq'::regclass);
 :   ALTER TABLE public.paiement ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    243    244    244                    2604    25043 
   patient id    DEFAULT     h   ALTER TABLE ONLY public.patient ALTER COLUMN id SET DEFAULT nextval('public.patient_id_seq'::regclass);
 9   ALTER TABLE public.patient ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    233    234    234         v           2604    24990    pharmacien id    DEFAULT     n   ALTER TABLE ONLY public.pharmacien ALTER COLUMN id SET DEFAULT nextval('public.pharmacien_id_seq'::regclass);
 <   ALTER TABLE public.pharmacien ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    225    226    226         �           2604    25052    prescription id    DEFAULT     r   ALTER TABLE ONLY public.prescription ALTER COLUMN id SET DEFAULT nextval('public.prescription_id_seq'::regclass);
 >   ALTER TABLE public.prescription ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    235    236    236         q           2604    24946    unite id    DEFAULT     d   ALTER TABLE ONLY public.unite ALTER COLUMN id SET DEFAULT nextval('public.unite_id_seq'::regclass);
 7   ALTER TABLE public.unite ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    218    217    218         t           2604    24981    utilisateur id    DEFAULT     p   ALTER TABLE ONLY public.utilisateur ALTER COLUMN id SET DEFAULT nextval('public.utilisateur_id_seq'::regclass);
 =   ALTER TABLE public.utilisateur ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    223    224    224         w           2604    25002 
   vendeur id    DEFAULT     h   ALTER TABLE ONLY public.vendeur ALTER COLUMN id SET DEFAULT nextval('public.vendeur_id_seq'::regclass);
 9   ALTER TABLE public.vendeur ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    227    228    228         �           2604    25064    vente id    DEFAULT     d   ALTER TABLE ONLY public.vente ALTER COLUMN id SET DEFAULT nextval('public.vente_id_seq'::regclass);
 7   ALTER TABLE public.vente ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    238    237    238         U          0    25011    commande 
   TABLE DATA           V   COPY public.commande (id, montant, date_creation, statut, fournisseur_id) FROM stdin;
    public          postgres    false    230       4949.dat a          0    25095    facture 
   TABLE DATA           Z   COPY public.facture (id, dateemission, montanttotal, numerofacture, vente_id) FROM stdin;
    public          postgres    false    242       4961.dat G          0    24936    famille 
   TABLE DATA           *   COPY public.famille (id, nom) FROM stdin;
    public          postgres    false    216       4935.dat K          0    24950    fournisseur 
   TABLE DATA           G   COPY public.fournisseur (id, nom, adresse, contact, email) FROM stdin;
    public          postgres    false    220       4939.dat W          0    25023    lignedecommande 
   TABLE DATA           �   COPY public.lignedecommande (id, quantitevendu, prixunitaire, commande_id, medicament_id, quantiterecue, prixachatreel, prixventereel) FROM stdin;
    public          postgres    false    232       4951.dat _          0    25078 
   lignevente 
   TABLE DATA           ^   COPY public.lignevente (id, quantitevendu, prixunitaire, vente_id, medicament_id) FROM stdin;
    public          postgres    false    240       4959.dat e          0    25119 	   livraison 
   TABLE DATA           [   COPY public.livraison (id, datelivraison, status, commande_id, fournisseur_id) FROM stdin;
    public          postgres    false    246       4965.dat M          0    24959 
   medicament 
   TABLE DATA           �   COPY public.medicament (id, nom, forme, prixachat, prixvente, stock, seuilcommande, qtemax, famille_id, fournisseur_id, ordonnance) FROM stdin;
    public          postgres    false    222       4941.dat c          0    25107    paiement 
   TABLE DATA           O   COPY public.paiement (id, montant, modepaiement, statut, vente_id) FROM stdin;
    public          postgres    false    244       4963.dat Y          0    25040    patient 
   TABLE DATA           S   COPY public.patient (id, nom, prenom, datenaissance, adresse, contact) FROM stdin;
    public          postgres    false    234       4953.dat Q          0    24987 
   pharmacien 
   TABLE DATA           8   COPY public.pharmacien (id, utilisateur_id) FROM stdin;
    public          postgres    false    226       4945.dat [          0    25049    prescription 
   TABLE DATA           T   COPY public.prescription (id, nommedecin, dateprescription, patient_id) FROM stdin;
    public          postgres    false    236       4955.dat I          0    24943    unite 
   TABLE DATA           -   COPY public.unite (id, nomunite) FROM stdin;
    public          postgres    false    218       4937.dat O          0    24978    utilisateur 
   TABLE DATA           H   COPY public.utilisateur (id, identifiant, motdepasse, role) FROM stdin;
    public          postgres    false    224       4943.dat S          0    24999    vendeur 
   TABLE DATA           5   COPY public.vendeur (id, utilisateur_id) FROM stdin;
    public          postgres    false    228       4947.dat ]          0    25061    vente 
   TABLE DATA           d   COPY public.vente (id, datevente, montanttotal, typevente, vendeur_id, prescription_id) FROM stdin;
    public          postgres    false    238       4957.dat }           0    0    commande_id_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('public.commande_id_seq', 2, true);
          public          postgres    false    229         ~           0    0    facture_id_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('public.facture_id_seq', 12, true);
          public          postgres    false    241                    0    0    famille_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.famille_id_seq', 1, true);
          public          postgres    false    215         �           0    0    fournisseur_id_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('public.fournisseur_id_seq', 3, true);
          public          postgres    false    219         �           0    0    lignedecommande_id_seq    SEQUENCE SET     D   SELECT pg_catalog.setval('public.lignedecommande_id_seq', 2, true);
          public          postgres    false    231         �           0    0    lignevente_id_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('public.lignevente_id_seq', 12, true);
          public          postgres    false    239         �           0    0    livraison_id_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.livraison_id_seq', 1, true);
          public          postgres    false    245         �           0    0    medicament_id_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.medicament_id_seq', 2, true);
          public          postgres    false    221         �           0    0    paiement_id_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.paiement_id_seq', 12, true);
          public          postgres    false    243         �           0    0    patient_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.patient_id_seq', 1, true);
          public          postgres    false    233         �           0    0    pharmacien_id_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.pharmacien_id_seq', 2, true);
          public          postgres    false    225         �           0    0    prescription_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.prescription_id_seq', 1, true);
          public          postgres    false    235         �           0    0    unite_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.unite_id_seq', 1, false);
          public          postgres    false    217         �           0    0    utilisateur_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.utilisateur_id_seq', 14, true);
          public          postgres    false    223         �           0    0    vendeur_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.vendeur_id_seq', 1, true);
          public          postgres    false    227         �           0    0    vente_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.vente_id_seq', 12, true);
          public          postgres    false    237         �           2606    25016    commande commande_pkey 
   CONSTRAINT     T   ALTER TABLE ONLY public.commande
    ADD CONSTRAINT commande_pkey PRIMARY KEY (id);
 @   ALTER TABLE ONLY public.commande DROP CONSTRAINT commande_pkey;
       public            postgres    false    230         �           2606    25100    facture facture_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.facture
    ADD CONSTRAINT facture_pkey PRIMARY KEY (id);
 >   ALTER TABLE ONLY public.facture DROP CONSTRAINT facture_pkey;
       public            postgres    false    242         �           2606    24941    famille famille_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.famille
    ADD CONSTRAINT famille_pkey PRIMARY KEY (id);
 >   ALTER TABLE ONLY public.famille DROP CONSTRAINT famille_pkey;
       public            postgres    false    216         �           2606    24957    fournisseur fournisseur_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY public.fournisseur
    ADD CONSTRAINT fournisseur_pkey PRIMARY KEY (id);
 F   ALTER TABLE ONLY public.fournisseur DROP CONSTRAINT fournisseur_pkey;
       public            postgres    false    220         �           2606    25028 $   lignedecommande lignedecommande_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY public.lignedecommande
    ADD CONSTRAINT lignedecommande_pkey PRIMARY KEY (id);
 N   ALTER TABLE ONLY public.lignedecommande DROP CONSTRAINT lignedecommande_pkey;
       public            postgres    false    232         �           2606    25083    lignevente lignevente_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY public.lignevente
    ADD CONSTRAINT lignevente_pkey PRIMARY KEY (id);
 D   ALTER TABLE ONLY public.lignevente DROP CONSTRAINT lignevente_pkey;
       public            postgres    false    240         �           2606    25124    livraison livraison_pkey 
   CONSTRAINT     V   ALTER TABLE ONLY public.livraison
    ADD CONSTRAINT livraison_pkey PRIMARY KEY (id);
 B   ALTER TABLE ONLY public.livraison DROP CONSTRAINT livraison_pkey;
       public            postgres    false    246         �           2606    24966    medicament medicament_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY public.medicament
    ADD CONSTRAINT medicament_pkey PRIMARY KEY (id);
 D   ALTER TABLE ONLY public.medicament DROP CONSTRAINT medicament_pkey;
       public            postgres    false    222         �           2606    25112    paiement paiement_pkey 
   CONSTRAINT     T   ALTER TABLE ONLY public.paiement
    ADD CONSTRAINT paiement_pkey PRIMARY KEY (id);
 @   ALTER TABLE ONLY public.paiement DROP CONSTRAINT paiement_pkey;
       public            postgres    false    244         �           2606    25047    patient patient_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.patient
    ADD CONSTRAINT patient_pkey PRIMARY KEY (id);
 >   ALTER TABLE ONLY public.patient DROP CONSTRAINT patient_pkey;
       public            postgres    false    234         �           2606    24992    pharmacien pharmacien_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY public.pharmacien
    ADD CONSTRAINT pharmacien_pkey PRIMARY KEY (id);
 D   ALTER TABLE ONLY public.pharmacien DROP CONSTRAINT pharmacien_pkey;
       public            postgres    false    226         �           2606    25054    prescription prescription_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.prescription
    ADD CONSTRAINT prescription_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.prescription DROP CONSTRAINT prescription_pkey;
       public            postgres    false    236         �           2606    24948    unite unite_pkey 
   CONSTRAINT     N   ALTER TABLE ONLY public.unite
    ADD CONSTRAINT unite_pkey PRIMARY KEY (id);
 :   ALTER TABLE ONLY public.unite DROP CONSTRAINT unite_pkey;
       public            postgres    false    218         �           2606    24985    utilisateur utilisateur_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY public.utilisateur
    ADD CONSTRAINT utilisateur_pkey PRIMARY KEY (id);
 F   ALTER TABLE ONLY public.utilisateur DROP CONSTRAINT utilisateur_pkey;
       public            postgres    false    224         �           2606    25004    vendeur vendeur_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.vendeur
    ADD CONSTRAINT vendeur_pkey PRIMARY KEY (id);
 >   ALTER TABLE ONLY public.vendeur DROP CONSTRAINT vendeur_pkey;
       public            postgres    false    228         �           2606    25066    vente vente_pkey 
   CONSTRAINT     N   ALTER TABLE ONLY public.vente
    ADD CONSTRAINT vente_pkey PRIMARY KEY (id);
 :   ALTER TABLE ONLY public.vente DROP CONSTRAINT vente_pkey;
       public            postgres    false    238         �           2620    50529 '   medicament trigger_commande_automatique    TRIGGER     �   CREATE TRIGGER trigger_commande_automatique AFTER UPDATE OF stock ON public.medicament FOR EACH ROW EXECUTE FUNCTION public.creer_commande_automatique();
 @   DROP TRIGGER trigger_commande_automatique ON public.medicament;
       public          postgres    false    259    222    222         �           2606    50515 %   commande commande_fournisseur_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.commande
    ADD CONSTRAINT commande_fournisseur_id_fkey FOREIGN KEY (fournisseur_id) REFERENCES public.fournisseur(id);
 O   ALTER TABLE ONLY public.commande DROP CONSTRAINT commande_fournisseur_id_fkey;
       public          postgres    false    220    230    4747         �           2606    25101    facture facture_vente_id_fkey    FK CONSTRAINT     }   ALTER TABLE ONLY public.facture
    ADD CONSTRAINT facture_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES public.vente(id);
 G   ALTER TABLE ONLY public.facture DROP CONSTRAINT facture_vente_id_fkey;
       public          postgres    false    4765    238    242         �           2606    25029 0   lignedecommande lignedecommande_commande_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.lignedecommande
    ADD CONSTRAINT lignedecommande_commande_id_fkey FOREIGN KEY (commande_id) REFERENCES public.commande(id);
 Z   ALTER TABLE ONLY public.lignedecommande DROP CONSTRAINT lignedecommande_commande_id_fkey;
       public          postgres    false    4757    230    232         �           2606    25034 2   lignedecommande lignedecommande_medicament_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.lignedecommande
    ADD CONSTRAINT lignedecommande_medicament_id_fkey FOREIGN KEY (medicament_id) REFERENCES public.medicament(id);
 \   ALTER TABLE ONLY public.lignedecommande DROP CONSTRAINT lignedecommande_medicament_id_fkey;
       public          postgres    false    222    232    4749         �           2606    25089 (   lignevente lignevente_medicament_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.lignevente
    ADD CONSTRAINT lignevente_medicament_id_fkey FOREIGN KEY (medicament_id) REFERENCES public.medicament(id);
 R   ALTER TABLE ONLY public.lignevente DROP CONSTRAINT lignevente_medicament_id_fkey;
       public          postgres    false    222    4749    240         �           2606    25084 #   lignevente lignevente_vente_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.lignevente
    ADD CONSTRAINT lignevente_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES public.vente(id);
 M   ALTER TABLE ONLY public.lignevente DROP CONSTRAINT lignevente_vente_id_fkey;
       public          postgres    false    238    240    4765         �           2606    25125 $   livraison livraison_commande_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.livraison
    ADD CONSTRAINT livraison_commande_id_fkey FOREIGN KEY (commande_id) REFERENCES public.commande(id);
 N   ALTER TABLE ONLY public.livraison DROP CONSTRAINT livraison_commande_id_fkey;
       public          postgres    false    230    4757    246         �           2606    25130 '   livraison livraison_fournisseur_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.livraison
    ADD CONSTRAINT livraison_fournisseur_id_fkey FOREIGN KEY (fournisseur_id) REFERENCES public.fournisseur(id);
 Q   ALTER TABLE ONLY public.livraison DROP CONSTRAINT livraison_fournisseur_id_fkey;
       public          postgres    false    220    246    4747         �           2606    24967 %   medicament medicament_famille_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.medicament
    ADD CONSTRAINT medicament_famille_id_fkey FOREIGN KEY (famille_id) REFERENCES public.famille(id);
 O   ALTER TABLE ONLY public.medicament DROP CONSTRAINT medicament_famille_id_fkey;
       public          postgres    false    4743    222    216         �           2606    24972 )   medicament medicament_fournisseur_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.medicament
    ADD CONSTRAINT medicament_fournisseur_id_fkey FOREIGN KEY (fournisseur_id) REFERENCES public.fournisseur(id);
 S   ALTER TABLE ONLY public.medicament DROP CONSTRAINT medicament_fournisseur_id_fkey;
       public          postgres    false    222    220    4747         �           2606    25113    paiement paiement_vente_id_fkey    FK CONSTRAINT        ALTER TABLE ONLY public.paiement
    ADD CONSTRAINT paiement_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES public.vente(id);
 I   ALTER TABLE ONLY public.paiement DROP CONSTRAINT paiement_vente_id_fkey;
       public          postgres    false    4765    238    244         �           2606    24993 )   pharmacien pharmacien_utilisateur_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.pharmacien
    ADD CONSTRAINT pharmacien_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES public.utilisateur(id);
 S   ALTER TABLE ONLY public.pharmacien DROP CONSTRAINT pharmacien_utilisateur_id_fkey;
       public          postgres    false    226    224    4751         �           2606    25055 )   prescription prescription_patient_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.prescription
    ADD CONSTRAINT prescription_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patient(id);
 S   ALTER TABLE ONLY public.prescription DROP CONSTRAINT prescription_patient_id_fkey;
       public          postgres    false    236    234    4761         �           2606    25005 #   vendeur vendeur_utilisateur_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.vendeur
    ADD CONSTRAINT vendeur_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES public.utilisateur(id);
 M   ALTER TABLE ONLY public.vendeur DROP CONSTRAINT vendeur_utilisateur_id_fkey;
       public          postgres    false    228    224    4751         �           2606    25072     vente vente_prescription_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.vente
    ADD CONSTRAINT vente_prescription_id_fkey FOREIGN KEY (prescription_id) REFERENCES public.prescription(id);
 J   ALTER TABLE ONLY public.vente DROP CONSTRAINT vente_prescription_id_fkey;
       public          postgres    false    236    4763    238         �           2606    25067    vente vente_vendeur_id_fkey    FK CONSTRAINT        ALTER TABLE ONLY public.vente
    ADD CONSTRAINT vente_vendeur_id_fkey FOREIGN KEY (vendeur_id) REFERENCES public.vendeur(id);
 E   ALTER TABLE ONLY public.vente DROP CONSTRAINT vente_vendeur_id_fkey;
       public          postgres    false    228    238    4755                                                                                                                                                                                     4949.dat                                                                                            0000600 0004000 0002000 00000000143 15000224312 0014246 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	2730.00	2025-04-01 14:29:05.1748	Validée	1
2	2880.00	2025-04-17 18:20:51.987488	Validée	1
\.


                                                                                                                                                                                                                                                                                                                                                                                                                             4961.dat                                                                                            0000600 0004000 0002000 00000001245 15000224312 0014244 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	2025-04-01 13:41:53.906	440.00	FAC-1-1743500513896	1
2	2025-04-01 13:42:35.025	800.00	FAC-2-1743500555025	2
3	2025-04-01 13:43:24.433	440.00	FAC-3-1743500604433	3
4	2025-04-01 14:28:41.907	440.00	FAC-4-1743503321896	4
5	2025-04-15 19:13:08.442	3880.00	FAC-5-1744729988418	5
6	2025-04-15 19:16:04.731	3640.00	FAC-6-1744730164722	6
7	2025-04-16 11:33:43.076	800.00	FAC-7-1744788823071	7
8	2025-04-16 11:40:40.556	1200.00	FAC-8-1744789240549	8
9	2025-04-16 11:48:24.833	200.00	FAC-9-1744789704827	9
10	2025-04-16 11:51:07.986	200.00	FAC-10-1744789867986	10
11	2025-04-17 18:20:10.904	400.00	FAC-11-1744899610895	11
12	2025-04-17 18:34:04.073	400.00	FAC-12-1744900444066	12
\.


                                                                                                                                                                                                                                                                                                                                                           4935.dat                                                                                            0000600 0004000 0002000 00000000023 15000224312 0014236 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	Paracetamol
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             4939.dat                                                                                            0000600 0004000 0002000 00000000116 15000224312 0014245 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	Chan	louis	5554470	sensiro456@gmail.com
3	ff	ff	7777777	kkkk@gmail.com
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                  4951.dat                                                                                            0000600 0004000 0002000 00000000073 15000224312 0014241 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	91	30.00	1	1	0	0.00	0.00
2	96	30.00	2	1	0	0.00	0.00
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                     4959.dat                                                                                            0000600 0004000 0002000 00000000275 15000224312 0014255 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	11	40.00	1	1
2	20	40.00	2	1
3	11	40.00	3	1
4	11	40.00	4	1
5	97	40.00	5	1
6	91	40.00	6	1
7	20	40.00	7	1
8	30	40.00	8	1
9	5	40.00	9	1
10	5	40.00	10	1
11	10	40.00	11	1
12	10	40.00	12	1
\.


                                                                                                                                                                                                                                                                                                                                   4965.dat                                                                                            0000600 0004000 0002000 00000000056 15000224312 0014247 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	2025-04-17 18:20:51.987488	Livrée	2	1
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  4941.dat                                                                                            0000600 0004000 0002000 00000000173 15000224312 0014241 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        2	Paracetamol 500mg	Comprimé	15.00	20.00	50	10	100	1	1	\N
1	Doliprane 1000 mg	Comprimé	30.00	40.00	90	10	100	1	1	\N
\.


                                                                                                                                                                                                                                                                                                                                                                                                     4963.dat                                                                                            0000600 0004000 0002000 00000000506 15000224312 0014245 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	440.00	ESPECES	VALIDE	1
2	440.00	ESPECES	VALIDE	4
3	3880.00	ESPECES	VALIDE	5
4	3640.00	ESPECES	VALIDE	6
5	800.00	ESPECES	VALIDE	2
6	440.00	ESPECES	VALIDE	3
7	800.00	ESPECES	VALIDE	7
8	1200.00	ESPECES	VALIDE	8
9	200.00	ESPECES	VALIDE	9
10	200.00	ESPECES	VALIDE	10
11	400.00	ESPECES	VALIDE	11
12	400.00	ESPECES	VALIDE	12
\.


                                                                                                                                                                                          4953.dat                                                                                            0000600 0004000 0002000 00000000057 15000224312 0014245 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	jackie	chan	2004-03-12	dessese	55522200
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 4945.dat                                                                                            0000600 0004000 0002000 00000000005 15000224312 0014237 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           4955.dat                                                                                            0000600 0004000 0002000 00000000043 15000224312 0014242 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	grand	2025-04-11 00:00:00	1
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             4937.dat                                                                                            0000600 0004000 0002000 00000000005 15000224312 0014240 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           4943.dat                                                                                            0000600 0004000 0002000 00000000127 15000224312 0014242 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	admin	admin123	PHARMACIEN
2	user1	user123	PHARMACIEN
3	user2	user234	PHARMACIEN
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                         4947.dat                                                                                            0000600 0004000 0002000 00000000005 15000224312 0014241 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           4957.dat                                                                                            0000600 0004000 0002000 00000000772 15000224312 0014255 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	2025-04-01 00:00:00	440.00	LIBRE	\N	\N
2	2025-04-01 00:00:00	800.00	LIBRE	\N	\N
3	2025-04-01 00:00:00	440.00	LIBRE	\N	\N
4	2025-04-01 00:00:00	440.00	LIBRE	\N	\N
5	2025-04-15 00:00:00	3880.00	LIBRE	\N	\N
6	2025-04-15 00:00:00	3640.00	LIBRE	\N	\N
7	2025-04-16 00:00:00	800.00	LIBRE	\N	\N
8	2025-04-16 00:00:00	1200.00	LIBRE	\N	\N
9	2025-04-16 00:00:00	200.00	PRESCRITE	\N	1
10	2025-04-16 00:00:00	200.00	LIBRE	\N	\N
11	2025-04-17 00:00:00	400.00	LIBRE	\N	\N
12	2025-04-17 00:00:00	400.00	LIBRE	\N	\N
\.


      restore.sql                                                                                         0000600 0004000 0002000 00000107672 15000224312 0015366 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        --
-- NOTE:
--
-- File paths need to be edited. Search for $$PATH$$ and
-- replace it with the path to the directory containing
-- the extracted data files.
--
--
-- PostgreSQL database dump
--

-- Dumped from database version 16.2
-- Dumped by pg_dump version 16.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE "PharmaGestBD";
--
-- Name: PharmaGestBD; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE "PharmaGestBD" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'French_France.1252';


ALTER DATABASE "PharmaGestBD" OWNER TO postgres;

\connect "PharmaGestBD"

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.role AS ENUM (
    'PHARMACIEN',
    'VENDEUR'
);


ALTER TYPE public.role OWNER TO postgres;

--
-- Name: statutpaiement; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.statutpaiement AS ENUM (
    'EN_ATTENTE',
    'VALIDE',
    'REJETE'
);


ALTER TYPE public.statutpaiement OWNER TO postgres;

--
-- Name: typevente; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.typevente AS ENUM (
    'LIBRE',
    'PRESCRITE'
);


ALTER TYPE public.typevente OWNER TO postgres;

--
-- Name: creer_commande_automatique(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.creer_commande_automatique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
v_fournisseur_id INTEGER;
v_commande_id INTEGER;
v_quantite_a_commander INTEGER;
v_prix_unitaire NUMERIC(10,2);
BEGIN
-- Ne déclencher que si le stock est passé sous le seuil de 10
IF NEW.stock < 10 AND (OLD.stock IS NULL OR OLD.stock >= 10) THEN
    -- Récupérer l'ID du fournisseur associé au médicament
    SELECT fournisseur_id INTO v_fournisseur_id FROM medicament WHERE id = NEW.id;
    
    -- Si pas de fournisseur assigné, utiliser un fournisseur par défaut
    IF v_fournisseur_id IS NULL THEN
        SELECT id INTO v_fournisseur_id FROM fournisseur LIMIT 1;
        
        IF v_fournisseur_id IS NULL THEN
            RAISE EXCEPTION 'Aucun fournisseur disponible pour créer une commande automatique';
            RETURN NEW;
        END IF;
        
        -- Mettre à jour le médicament avec ce fournisseur
        UPDATE medicament SET fournisseur_id = v_fournisseur_id WHERE id = NEW.id;
    END IF;
    
    -- Calculer la quantité à commander (pour atteindre 100)
    v_quantite_a_commander := 100 - NEW.stock;
    
    -- Récupérer le prix d'achat du médicament
    v_prix_unitaire := NEW.prixachat;
    
    -- Vérifier si une commande en attente existe déjà pour ce fournisseur
    SELECT id INTO v_commande_id 
    FROM commande 
    WHERE fournisseur_id = v_fournisseur_id 
      AND statut = 'En attente de confirmation'
    LIMIT 1;
    
    -- Si aucune commande en attente n'existe, en créer une nouvelle
    IF v_commande_id IS NULL THEN
        INSERT INTO commande (montant, fournisseur_id, date_creation, statut)
        VALUES (0, v_fournisseur_id, CURRENT_TIMESTAMP, 'En attente de confirmation')
        RETURNING id INTO v_commande_id;
        
        -- Créer une livraison associée à cette commande avec statut "En cours"
        INSERT INTO livraison (datelivraison, status, commande_id, fournisseur_id)
        VALUES (CURRENT_TIMESTAMP, 'En cours', v_commande_id, v_fournisseur_id);
        
        RAISE NOTICE 'Nouvelle commande créée (ID: %) pour le fournisseur % avec livraison associée', v_commande_id, v_fournisseur_id;
    ELSE
        RAISE NOTICE 'Ajout à une commande existante (ID: %) pour le fournisseur %', v_commande_id, v_fournisseur_id;
    END IF;
    
    -- Vérifier si ce médicament est déjà dans la commande
    IF EXISTS (SELECT 1 FROM lignedecommande WHERE commande_id = v_commande_id AND medicament_id = NEW.id) THEN
        -- Mettre à jour la ligne de commande existante
        UPDATE lignedecommande 
        SET quantitevendu = quantitevendu + v_quantite_a_commander
        WHERE commande_id = v_commande_id AND medicament_id = NEW.id;
        
        RAISE NOTICE 'Mise à jour de la quantité pour le médicament % dans la commande %', NEW.id, v_commande_id;
    ELSE
        -- Ajouter une nouvelle ligne de commande
        INSERT INTO lignedecommande (quantitevendu, prixunitaire, commande_id, medicament_id, quantiterecue, prixachatreel, prixventereel)
        VALUES (v_quantite_a_commander, v_prix_unitaire, v_commande_id, NEW.id, 0, 0, 0);
        
        RAISE NOTICE 'Ajout du médicament % à la commande %', NEW.id, v_commande_id;
    END IF;
    
    -- Mettre à jour le montant total de la commande
    UPDATE commande
    SET montant = (
        SELECT SUM(quantitevendu * prixunitaire)
        FROM lignedecommande
        WHERE commande_id = v_commande_id
    )
    WHERE id = v_commande_id;
    
    RAISE NOTICE 'Commande automatique créée/mise à jour pour le médicament % (stock: %)', NEW.nom, NEW.stock;
END IF;

RETURN NEW;
END;
$$;


ALTER FUNCTION public.creer_commande_automatique() OWNER TO postgres;

--
-- Name: valider_commande(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.valider_commande(p_commande_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
r_ligne RECORD;
v_livraison_id INTEGER;
BEGIN
-- Vérifier que la commande existe et est en attente
IF NOT EXISTS (SELECT 1 FROM commande WHERE id = p_commande_id AND statut = 'En attente de confirmation') THEN
    RAISE EXCEPTION 'Commande % inexistante ou déjà validée', p_commande_id;
END IF;

-- Pour chaque ligne de commande, mettre à jour le stock du médicament
FOR r_ligne IN (SELECT medicament_id, quantitevendu FROM lignedecommande WHERE commande_id = p_commande_id) LOOP
    UPDATE medicament
    SET stock = stock + r_ligne.quantitevendu
    WHERE id = r_ligne.medicament_id;
    
    RAISE NOTICE 'Stock du médicament % mis à jour', r_ligne.medicament_id;
END LOOP;

-- Marquer la commande comme validée
UPDATE commande
SET statut = 'Validée'
WHERE id = p_commande_id;

-- Mettre à jour le statut de la livraison associée à "Livrée"
SELECT id INTO v_livraison_id FROM livraison WHERE commande_id = p_commande_id;
IF v_livraison_id IS NOT NULL THEN
    UPDATE livraison
    SET status = 'Livrée'
    WHERE id = v_livraison_id;
    
    RAISE NOTICE 'Livraison % associée à la commande % marquée comme livrée', v_livraison_id, p_commande_id;
END IF;

RAISE NOTICE 'Commande % validée avec succès', p_commande_id;
END;
$$;


ALTER FUNCTION public.valider_commande(p_commande_id integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: commande; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.commande (
    id integer NOT NULL,
    montant numeric(10,2) NOT NULL,
    date_creation timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    statut character varying(50) DEFAULT 'En attente de confirmation'::character varying,
    fournisseur_id integer
);


ALTER TABLE public.commande OWNER TO postgres;

--
-- Name: commande_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.commande_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.commande_id_seq OWNER TO postgres;

--
-- Name: commande_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.commande_id_seq OWNED BY public.commande.id;


--
-- Name: facture; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.facture (
    id integer NOT NULL,
    dateemission timestamp without time zone NOT NULL,
    montanttotal numeric(10,2) NOT NULL,
    numerofacture character varying(255) NOT NULL,
    vente_id integer
);


ALTER TABLE public.facture OWNER TO postgres;

--
-- Name: facture_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.facture_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.facture_id_seq OWNER TO postgres;

--
-- Name: facture_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.facture_id_seq OWNED BY public.facture.id;


--
-- Name: famille; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.famille (
    id integer NOT NULL,
    nom character varying(255) NOT NULL
);


ALTER TABLE public.famille OWNER TO postgres;

--
-- Name: famille_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.famille_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.famille_id_seq OWNER TO postgres;

--
-- Name: famille_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.famille_id_seq OWNED BY public.famille.id;


--
-- Name: fournisseur; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fournisseur (
    id integer NOT NULL,
    nom character varying(255) NOT NULL,
    adresse character varying(255),
    contact character varying(255),
    email character varying
);


ALTER TABLE public.fournisseur OWNER TO postgres;

--
-- Name: fournisseur_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.fournisseur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.fournisseur_id_seq OWNER TO postgres;

--
-- Name: fournisseur_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.fournisseur_id_seq OWNED BY public.fournisseur.id;


--
-- Name: lignedecommande; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lignedecommande (
    id integer NOT NULL,
    quantitevendu integer NOT NULL,
    prixunitaire numeric(10,2) NOT NULL,
    commande_id integer,
    medicament_id integer,
    quantiterecue integer DEFAULT 0,
    prixachatreel numeric(10,2) DEFAULT 0,
    prixventereel numeric(10,2) DEFAULT 0
);


ALTER TABLE public.lignedecommande OWNER TO postgres;

--
-- Name: lignedecommande_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lignedecommande_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lignedecommande_id_seq OWNER TO postgres;

--
-- Name: lignedecommande_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lignedecommande_id_seq OWNED BY public.lignedecommande.id;


--
-- Name: lignevente; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lignevente (
    id integer NOT NULL,
    quantitevendu integer NOT NULL,
    prixunitaire numeric(10,2) NOT NULL,
    vente_id integer,
    medicament_id integer
);


ALTER TABLE public.lignevente OWNER TO postgres;

--
-- Name: lignevente_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lignevente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lignevente_id_seq OWNER TO postgres;

--
-- Name: lignevente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lignevente_id_seq OWNED BY public.lignevente.id;


--
-- Name: livraison; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.livraison (
    id integer NOT NULL,
    datelivraison timestamp without time zone NOT NULL,
    status character varying(255),
    commande_id integer,
    fournisseur_id integer
);


ALTER TABLE public.livraison OWNER TO postgres;

--
-- Name: livraison_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.livraison_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.livraison_id_seq OWNER TO postgres;

--
-- Name: livraison_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.livraison_id_seq OWNED BY public.livraison.id;


--
-- Name: medicament; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.medicament (
    id integer NOT NULL,
    nom character varying(255) NOT NULL,
    forme character varying(255),
    prixachat numeric(10,2) NOT NULL,
    prixvente numeric(10,2) NOT NULL,
    stock integer NOT NULL,
    seuilcommande integer NOT NULL,
    qtemax integer NOT NULL,
    famille_id integer,
    fournisseur_id integer NOT NULL,
    ordonnance boolean
);


ALTER TABLE public.medicament OWNER TO postgres;

--
-- Name: medicament_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.medicament_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.medicament_id_seq OWNER TO postgres;

--
-- Name: medicament_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.medicament_id_seq OWNED BY public.medicament.id;


--
-- Name: paiement; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.paiement (
    id integer NOT NULL,
    montant numeric(10,2) NOT NULL,
    modepaiement character varying(255),
    statut public.statutpaiement NOT NULL,
    vente_id integer
);


ALTER TABLE public.paiement OWNER TO postgres;

--
-- Name: paiement_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.paiement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.paiement_id_seq OWNER TO postgres;

--
-- Name: paiement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.paiement_id_seq OWNED BY public.paiement.id;


--
-- Name: patient; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patient (
    id integer NOT NULL,
    nom character varying(255) NOT NULL,
    prenom character varying(255) NOT NULL,
    datenaissance date NOT NULL,
    adresse character varying(255),
    contact character varying(255)
);


ALTER TABLE public.patient OWNER TO postgres;

--
-- Name: patient_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.patient_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_id_seq OWNER TO postgres;

--
-- Name: patient_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.patient_id_seq OWNED BY public.patient.id;


--
-- Name: pharmacien; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pharmacien (
    id integer NOT NULL,
    utilisateur_id integer
);


ALTER TABLE public.pharmacien OWNER TO postgres;

--
-- Name: pharmacien_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pharmacien_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pharmacien_id_seq OWNER TO postgres;

--
-- Name: pharmacien_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pharmacien_id_seq OWNED BY public.pharmacien.id;


--
-- Name: prescription; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.prescription (
    id integer NOT NULL,
    nommedecin character varying(255) NOT NULL,
    dateprescription timestamp without time zone NOT NULL,
    patient_id integer
);


ALTER TABLE public.prescription OWNER TO postgres;

--
-- Name: prescription_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.prescription_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.prescription_id_seq OWNER TO postgres;

--
-- Name: prescription_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.prescription_id_seq OWNED BY public.prescription.id;


--
-- Name: unite; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.unite (
    id integer NOT NULL,
    nomunite character varying(255) NOT NULL
);


ALTER TABLE public.unite OWNER TO postgres;

--
-- Name: unite_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.unite_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.unite_id_seq OWNER TO postgres;

--
-- Name: unite_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.unite_id_seq OWNED BY public.unite.id;


--
-- Name: utilisateur; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.utilisateur (
    id integer NOT NULL,
    identifiant character varying(255) NOT NULL,
    motdepasse character varying(255) NOT NULL,
    role public.role DEFAULT 'PHARMACIEN'::public.role
);


ALTER TABLE public.utilisateur OWNER TO postgres;

--
-- Name: utilisateur_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.utilisateur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.utilisateur_id_seq OWNER TO postgres;

--
-- Name: utilisateur_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.utilisateur_id_seq OWNED BY public.utilisateur.id;


--
-- Name: vendeur; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vendeur (
    id integer NOT NULL,
    utilisateur_id integer
);


ALTER TABLE public.vendeur OWNER TO postgres;

--
-- Name: vendeur_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vendeur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vendeur_id_seq OWNER TO postgres;

--
-- Name: vendeur_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vendeur_id_seq OWNED BY public.vendeur.id;


--
-- Name: vente; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vente (
    id integer NOT NULL,
    datevente timestamp without time zone NOT NULL,
    montanttotal numeric(10,2) NOT NULL,
    typevente public.typevente NOT NULL,
    vendeur_id integer,
    prescription_id integer
);


ALTER TABLE public.vente OWNER TO postgres;

--
-- Name: vente_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vente_id_seq OWNER TO postgres;

--
-- Name: vente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vente_id_seq OWNED BY public.vente.id;


--
-- Name: commande id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.commande ALTER COLUMN id SET DEFAULT nextval('public.commande_id_seq'::regclass);


--
-- Name: facture id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facture ALTER COLUMN id SET DEFAULT nextval('public.facture_id_seq'::regclass);


--
-- Name: famille id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.famille ALTER COLUMN id SET DEFAULT nextval('public.famille_id_seq'::regclass);


--
-- Name: fournisseur id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fournisseur ALTER COLUMN id SET DEFAULT nextval('public.fournisseur_id_seq'::regclass);


--
-- Name: lignedecommande id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignedecommande ALTER COLUMN id SET DEFAULT nextval('public.lignedecommande_id_seq'::regclass);


--
-- Name: lignevente id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignevente ALTER COLUMN id SET DEFAULT nextval('public.lignevente_id_seq'::regclass);


--
-- Name: livraison id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.livraison ALTER COLUMN id SET DEFAULT nextval('public.livraison_id_seq'::regclass);


--
-- Name: medicament id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicament ALTER COLUMN id SET DEFAULT nextval('public.medicament_id_seq'::regclass);


--
-- Name: paiement id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paiement ALTER COLUMN id SET DEFAULT nextval('public.paiement_id_seq'::regclass);


--
-- Name: patient id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient ALTER COLUMN id SET DEFAULT nextval('public.patient_id_seq'::regclass);


--
-- Name: pharmacien id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pharmacien ALTER COLUMN id SET DEFAULT nextval('public.pharmacien_id_seq'::regclass);


--
-- Name: prescription id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription ALTER COLUMN id SET DEFAULT nextval('public.prescription_id_seq'::regclass);


--
-- Name: unite id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.unite ALTER COLUMN id SET DEFAULT nextval('public.unite_id_seq'::regclass);


--
-- Name: utilisateur id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.utilisateur ALTER COLUMN id SET DEFAULT nextval('public.utilisateur_id_seq'::regclass);


--
-- Name: vendeur id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendeur ALTER COLUMN id SET DEFAULT nextval('public.vendeur_id_seq'::regclass);


--
-- Name: vente id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vente ALTER COLUMN id SET DEFAULT nextval('public.vente_id_seq'::regclass);


--
-- Data for Name: commande; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.commande (id, montant, date_creation, statut, fournisseur_id) FROM stdin;
\.
COPY public.commande (id, montant, date_creation, statut, fournisseur_id) FROM '$$PATH$$/4949.dat';

--
-- Data for Name: facture; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.facture (id, dateemission, montanttotal, numerofacture, vente_id) FROM stdin;
\.
COPY public.facture (id, dateemission, montanttotal, numerofacture, vente_id) FROM '$$PATH$$/4961.dat';

--
-- Data for Name: famille; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.famille (id, nom) FROM stdin;
\.
COPY public.famille (id, nom) FROM '$$PATH$$/4935.dat';

--
-- Data for Name: fournisseur; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fournisseur (id, nom, adresse, contact, email) FROM stdin;
\.
COPY public.fournisseur (id, nom, adresse, contact, email) FROM '$$PATH$$/4939.dat';

--
-- Data for Name: lignedecommande; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lignedecommande (id, quantitevendu, prixunitaire, commande_id, medicament_id, quantiterecue, prixachatreel, prixventereel) FROM stdin;
\.
COPY public.lignedecommande (id, quantitevendu, prixunitaire, commande_id, medicament_id, quantiterecue, prixachatreel, prixventereel) FROM '$$PATH$$/4951.dat';

--
-- Data for Name: lignevente; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lignevente (id, quantitevendu, prixunitaire, vente_id, medicament_id) FROM stdin;
\.
COPY public.lignevente (id, quantitevendu, prixunitaire, vente_id, medicament_id) FROM '$$PATH$$/4959.dat';

--
-- Data for Name: livraison; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.livraison (id, datelivraison, status, commande_id, fournisseur_id) FROM stdin;
\.
COPY public.livraison (id, datelivraison, status, commande_id, fournisseur_id) FROM '$$PATH$$/4965.dat';

--
-- Data for Name: medicament; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medicament (id, nom, forme, prixachat, prixvente, stock, seuilcommande, qtemax, famille_id, fournisseur_id, ordonnance) FROM stdin;
\.
COPY public.medicament (id, nom, forme, prixachat, prixvente, stock, seuilcommande, qtemax, famille_id, fournisseur_id, ordonnance) FROM '$$PATH$$/4941.dat';

--
-- Data for Name: paiement; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.paiement (id, montant, modepaiement, statut, vente_id) FROM stdin;
\.
COPY public.paiement (id, montant, modepaiement, statut, vente_id) FROM '$$PATH$$/4963.dat';

--
-- Data for Name: patient; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.patient (id, nom, prenom, datenaissance, adresse, contact) FROM stdin;
\.
COPY public.patient (id, nom, prenom, datenaissance, adresse, contact) FROM '$$PATH$$/4953.dat';

--
-- Data for Name: pharmacien; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pharmacien (id, utilisateur_id) FROM stdin;
\.
COPY public.pharmacien (id, utilisateur_id) FROM '$$PATH$$/4945.dat';

--
-- Data for Name: prescription; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.prescription (id, nommedecin, dateprescription, patient_id) FROM stdin;
\.
COPY public.prescription (id, nommedecin, dateprescription, patient_id) FROM '$$PATH$$/4955.dat';

--
-- Data for Name: unite; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.unite (id, nomunite) FROM stdin;
\.
COPY public.unite (id, nomunite) FROM '$$PATH$$/4937.dat';

--
-- Data for Name: utilisateur; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.utilisateur (id, identifiant, motdepasse, role) FROM stdin;
\.
COPY public.utilisateur (id, identifiant, motdepasse, role) FROM '$$PATH$$/4943.dat';

--
-- Data for Name: vendeur; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vendeur (id, utilisateur_id) FROM stdin;
\.
COPY public.vendeur (id, utilisateur_id) FROM '$$PATH$$/4947.dat';

--
-- Data for Name: vente; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vente (id, datevente, montanttotal, typevente, vendeur_id, prescription_id) FROM stdin;
\.
COPY public.vente (id, datevente, montanttotal, typevente, vendeur_id, prescription_id) FROM '$$PATH$$/4957.dat';

--
-- Name: commande_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.commande_id_seq', 2, true);


--
-- Name: facture_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.facture_id_seq', 12, true);


--
-- Name: famille_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.famille_id_seq', 1, true);


--
-- Name: fournisseur_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.fournisseur_id_seq', 3, true);


--
-- Name: lignedecommande_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lignedecommande_id_seq', 2, true);


--
-- Name: lignevente_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lignevente_id_seq', 12, true);


--
-- Name: livraison_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.livraison_id_seq', 1, true);


--
-- Name: medicament_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.medicament_id_seq', 2, true);


--
-- Name: paiement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.paiement_id_seq', 12, true);


--
-- Name: patient_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.patient_id_seq', 1, true);


--
-- Name: pharmacien_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pharmacien_id_seq', 2, true);


--
-- Name: prescription_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.prescription_id_seq', 1, true);


--
-- Name: unite_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.unite_id_seq', 1, false);


--
-- Name: utilisateur_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.utilisateur_id_seq', 14, true);


--
-- Name: vendeur_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vendeur_id_seq', 1, true);


--
-- Name: vente_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vente_id_seq', 12, true);


--
-- Name: commande commande_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.commande
    ADD CONSTRAINT commande_pkey PRIMARY KEY (id);


--
-- Name: facture facture_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facture
    ADD CONSTRAINT facture_pkey PRIMARY KEY (id);


--
-- Name: famille famille_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.famille
    ADD CONSTRAINT famille_pkey PRIMARY KEY (id);


--
-- Name: fournisseur fournisseur_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fournisseur
    ADD CONSTRAINT fournisseur_pkey PRIMARY KEY (id);


--
-- Name: lignedecommande lignedecommande_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignedecommande
    ADD CONSTRAINT lignedecommande_pkey PRIMARY KEY (id);


--
-- Name: lignevente lignevente_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignevente
    ADD CONSTRAINT lignevente_pkey PRIMARY KEY (id);


--
-- Name: livraison livraison_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.livraison
    ADD CONSTRAINT livraison_pkey PRIMARY KEY (id);


--
-- Name: medicament medicament_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicament
    ADD CONSTRAINT medicament_pkey PRIMARY KEY (id);


--
-- Name: paiement paiement_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paiement
    ADD CONSTRAINT paiement_pkey PRIMARY KEY (id);


--
-- Name: patient patient_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient
    ADD CONSTRAINT patient_pkey PRIMARY KEY (id);


--
-- Name: pharmacien pharmacien_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pharmacien
    ADD CONSTRAINT pharmacien_pkey PRIMARY KEY (id);


--
-- Name: prescription prescription_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription
    ADD CONSTRAINT prescription_pkey PRIMARY KEY (id);


--
-- Name: unite unite_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.unite
    ADD CONSTRAINT unite_pkey PRIMARY KEY (id);


--
-- Name: utilisateur utilisateur_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.utilisateur
    ADD CONSTRAINT utilisateur_pkey PRIMARY KEY (id);


--
-- Name: vendeur vendeur_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendeur
    ADD CONSTRAINT vendeur_pkey PRIMARY KEY (id);


--
-- Name: vente vente_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vente
    ADD CONSTRAINT vente_pkey PRIMARY KEY (id);


--
-- Name: medicament trigger_commande_automatique; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_commande_automatique AFTER UPDATE OF stock ON public.medicament FOR EACH ROW EXECUTE FUNCTION public.creer_commande_automatique();


--
-- Name: commande commande_fournisseur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.commande
    ADD CONSTRAINT commande_fournisseur_id_fkey FOREIGN KEY (fournisseur_id) REFERENCES public.fournisseur(id);


--
-- Name: facture facture_vente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facture
    ADD CONSTRAINT facture_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES public.vente(id);


--
-- Name: lignedecommande lignedecommande_commande_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignedecommande
    ADD CONSTRAINT lignedecommande_commande_id_fkey FOREIGN KEY (commande_id) REFERENCES public.commande(id);


--
-- Name: lignedecommande lignedecommande_medicament_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignedecommande
    ADD CONSTRAINT lignedecommande_medicament_id_fkey FOREIGN KEY (medicament_id) REFERENCES public.medicament(id);


--
-- Name: lignevente lignevente_medicament_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignevente
    ADD CONSTRAINT lignevente_medicament_id_fkey FOREIGN KEY (medicament_id) REFERENCES public.medicament(id);


--
-- Name: lignevente lignevente_vente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lignevente
    ADD CONSTRAINT lignevente_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES public.vente(id);


--
-- Name: livraison livraison_commande_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.livraison
    ADD CONSTRAINT livraison_commande_id_fkey FOREIGN KEY (commande_id) REFERENCES public.commande(id);


--
-- Name: livraison livraison_fournisseur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.livraison
    ADD CONSTRAINT livraison_fournisseur_id_fkey FOREIGN KEY (fournisseur_id) REFERENCES public.fournisseur(id);


--
-- Name: medicament medicament_famille_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicament
    ADD CONSTRAINT medicament_famille_id_fkey FOREIGN KEY (famille_id) REFERENCES public.famille(id);


--
-- Name: medicament medicament_fournisseur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicament
    ADD CONSTRAINT medicament_fournisseur_id_fkey FOREIGN KEY (fournisseur_id) REFERENCES public.fournisseur(id);


--
-- Name: paiement paiement_vente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paiement
    ADD CONSTRAINT paiement_vente_id_fkey FOREIGN KEY (vente_id) REFERENCES public.vente(id);


--
-- Name: pharmacien pharmacien_utilisateur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pharmacien
    ADD CONSTRAINT pharmacien_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES public.utilisateur(id);


--
-- Name: prescription prescription_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription
    ADD CONSTRAINT prescription_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patient(id);


--
-- Name: vendeur vendeur_utilisateur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendeur
    ADD CONSTRAINT vendeur_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES public.utilisateur(id);


--
-- Name: vente vente_prescription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vente
    ADD CONSTRAINT vente_prescription_id_fkey FOREIGN KEY (prescription_id) REFERENCES public.prescription(id);


--
-- Name: vente vente_vendeur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vente
    ADD CONSTRAINT vente_vendeur_id_fkey FOREIGN KEY (vendeur_id) REFERENCES public.vendeur(id);


--
-- PostgreSQL database dump complete
--

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      