import React, { useState, useEffect } from 'react';
import { Menu, X, ChevronDown, Check, Star, Phone, MessageCircle, Zap } from 'lucide-react';

// ============================================
// CONFIGURATION AFRICAINE
// ============================================

const CONFIG = {
  brand: {
    name: "EdonApp",
    logo: "✨",
    slogan: "Commandes rapides. Paiements sécurisés. Zéro erreur.",
    description: "Créez votre boutique sur WhatsApp"
  },

  colors: {
    primary: "pink-600",
    secondary: "purple-600",
    accent: "amber-500",
    background: "rose-50",
    text: "slate-900"
  },

  hero: {
    title: "Créez Votre Boutique WhatsApp",
    subtitle: "Recevez vos commandes et paiements en ligne",
    tagline: "Simple, rapide, et efficace pour l'Afrique",
    ctaButton: "Commencer gratuitement",
    partnerBadge: "🌍 Solution Africaine",
    partners: [
      { name: "Mobile Money", color: "orange-600" },
      { name: "WhatsApp Business", color: "green-600" },
      { name: "Paiements Locaux", color: "blue-600" }
    ]
  },

  contact: {
    signupUrl: "#inscription",
    loginUrl: "#connexion",
    salesUrl: "https://wa.me/237670000000", // Remplacez par votre numéro WhatsApp
    phone: "+237 670 000 000",
    email: "contact@glowshop.com"
  }
};

const FEATURES = [
  {
    icon: "📱",
    title: "Commandes WhatsApp Claires",
    description: "Vos clients passent commande directement sur WhatsApp avec tous les détails : produits, quantités, horaires de livraison. Fini les messages confus !",
    gradient: "from-pink-50 to-rose-100",
    color: "pink"
  },
  {
    icon: "💰",
    title: "Paiements Mobile Money",
    description: "Acceptez Orange Money, MTN Money, Wave, Moov Money et autres solutions de paiement mobile. Vos clients paient en 2 clics !",
    gradient: "from-orange-50 to-amber-100",
    color: "orange"
  },
  {
    icon: "📊",
    title: "Gestion des Commandes",
    description: "Suivez toutes vos commandes en temps réel depuis votre tableau de bord. Statut, historique, factures, tout est organisé.",
    gradient: "from-purple-50 to-violet-100",
    color: "purple"
  }
];

const WHATSAPP_FEATURES = [
  {
    icon: "🔔",
    title: "Relance Automatique",
    description: "Relancez automatiquement les clients qui n'ont pas payé. Augmentez vos ventes de 30% en moyenne.",
    color: "green"
  },
  {
    icon: "📢",
    title: "Messages de Groupe",
    description: "Envoyez des promotions à tous vos clients en même temps. Idéal pour les nouveaux produits et les offres spéciales.",
    color: "blue"
  },
  {
    icon: "🤖",
    title: "Réponses Automatiques",
    description: "Configurez des réponses automatiques pour les questions fréquentes. Gagnez du temps et améliorez le service.",
    color: "purple"
  }
];

const TESTIMONIALS = [
  {
    name: "Aminata Diallo",
    company: "Beauté d'Afrique",
    role: "Fondatrice",
    country: "🇸🇳 Sénégal",
    quote: "Mes ventes ont triplé en 2 mois ! Les clientes adorent commander sur WhatsApp. Je recommande à 100%.",
    avatar: "💄",
    rating: 5
  },
  {
    name: "Kouadio Marcel",
    company: "Fashion Abidjan",
    role: "Gérant",
    country: "🇨🇮 Côte d'Ivoire",
    quote: "Plus besoin de gérer les commandes dans ma tête. Tout est clair et organisé. Mon chiffre d'affaires a doublé !",
    avatar: "👔",
    rating: 5
  },
  {
    name: "Fatou Ndiaye",
    company: "Cosmetiques Plus",
    role: "Directrice",
    country: "🇨🇲 Cameroun",
    quote: "Le paiement Mobile Money a tout changé. Mes clients paient directement et je reçois l'argent instantanément.",
    avatar: "💅",
    rating: 5
  },
  {
    name: "Ousmane Traoré",
    company: "TechPhone BF",
    role: "Propriétaire",
    country: "🇧🇫 Burkina Faso",
    quote: "Solution parfaite pour mon business ! Interface simple et mes clients sont satisfaits. Merci GlowShop !",
    avatar: "📱",
    rating: 5
  },
  {
    name: "Marie-Claire Kaboré",
    company: "Délices du Sahel",
    role: "Chef Pâtissière",
    country: "🇳🇪 Niger",
    quote: "Je gère mes commandes de gâteaux facilement. Les clients voient les photos et commandent en 1 clic !",
    avatar: "🎂",
    rating: 5
  },
  {
    name: "Ibrahim Sanogo",
    company: "Mode & Style",
    role: "Designer",
    country: "🇲🇱 Mali",
    quote: "Excellent outil pour développer mon business en ligne. Tout est automatisé et professionnel.",
    avatar: "👗",
    rating: 5
  }
];

const PRICING_PLANS = [
  {
    name: "Gratuit",
    monthlyPrice: 0,
    annualPrice: 0,
    currency: "F CFA",
    description: "Parfait pour démarrer",
    features: [
      "50 commandes par mois",
      "Site web avec 20 photos",
      "Aucune commission",
      "Paiement Mobile Money",
      "Support par email",
      "Catalogue produits basique"
    ],
    ctaText: "Commencer gratuitement",
    highlighted: false,
    popularBadge: false,
    savings: null
  },
  {
    name: "Professionnel",
    monthlyPrice: 15000,
    annualPrice: 150000,
    currency: "F CFA",
    description: "Tout du Gratuit plus :",
    features: [
      "Commandes illimitées",
      "Photos illimitées",
      "Paiements par carte (Visa, Mastercard)",
      "Automatisation WhatsApp",
      "Nom de domaine personnalisé",
      "Suppression du logo GlowShop",
      "Plusieurs boutiques et employés",
      "Support prioritaire 24/7",
      "Statistiques avancées",
      "Formation vidéo gratuite"
    ],
    ctaText: "Démarrer maintenant",
    highlighted: true,
    popularBadge: true,
    savings: "Économisez 30 000 F CFA"
  },
  {
    name: "Entreprise",
    monthlyPrice: null,
    annualPrice: null,
    currency: "F CFA",
    description: "Tout du Professionnel plus :",
    features: [
      "Gestionnaire de compte dédié",
      "Plans et tarifs sur mesure",
      "Intégration API personnalisée",
      "Formation de votre équipe",
      "Développement de fonctionnalités spéciales"
    ],
    ctaText: "Contactez les ventes",
    highlighted: false,
    popularBadge: false,
    savings: null
  }
];

const FAQ_ITEMS = [
  {
    question: "Est-ce que GlowShop fonctionne dans mon pays ?",
    answer: "Oui ! GlowShop fonctionne dans tous les pays africains. Nous supportons Orange Money, MTN Money, Wave, Moov Money et toutes les solutions de paiement mobile locales."
  },
  {
    question: "Comment mes clients vont passer commande ?",
    answer: "C'est très simple : vos clients cliquent sur votre lien, choisissent les produits, remplissent leurs informations et envoient la commande sur WhatsApp. Vous recevez tout directement !"
  },
  {
    question: "Est-ce que je dois signer un contrat longue durée ?",
    answer: "Non ! Vous pouvez commencer gratuitement et payer mois par mois. Les plans annuels sont optionnels et vous font économiser 25%."
  },
  {
    question: "Comment je reçois l'argent de mes ventes ?",
    answer: "L'argent arrive directement dans votre compte Mobile Money ou bancaire. Nous ne gardons jamais votre argent. Vous êtes payé instantanément !"
  },
  {
    question: "Puis-je utiliser mon propre nom de domaine ?",
    answer: "Oui ! Avec le plan Professionnel, vous pouvez acheter un domaine via GlowShop ou connecter votre domaine existant (exemple : maboutique.com)."
  },
  {
    question: "Si j'ai besoin d'aide, vous répondez vite ?",
    answer: "Oui ! Support gratuit par chat en quelques heures. Les plans payants ont un support prioritaire par WhatsApp, téléphone et vidéo en direct."
  },
  {
    question: "Je ne suis pas très doué en informatique, c'est compliqué ?",
    answer: "Pas du tout ! GlowShop est fait pour les débutants. Vous créez votre boutique en 15 minutes. Nous avons aussi des vidéos de formation gratuites."
  },
  {
    question: "Quels sont les moyens de paiement acceptés ?",
    answer: "Nous acceptons tous les moyens de paiement africains : Orange Money, MTN Money, Wave, Moov Money, et aussi Visa/Mastercard pour vos clients."
  }
];

const PAYMENT_METHODS = [
  { name: "Orange Money", color: "orange-500", icon: "📱" },
  { name: "MTN Money", color: "yellow-500", icon: "💳" },
  { name: "Wave", color: "blue-500", icon: "🌊" },
  { name: "Moov Money", color: "green-500", icon: "💰" },
  { name: "Visa", color: "blue-600", icon: "💳" },
  { name: "Mastercard", color: "red-500", icon: "💳" }
];

// ============================================
// COMPOSANT PRINCIPAL
// ============================================

export default function GlowShopAfrica() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [isAnnual, setIsAnnual] = useState(false);
  const [activeTestimonial, setActiveTestimonial] = useState(0);

  useEffect(() => {
    const interval = setInterval(() => {
      setActiveTestimonial(prev => (prev + 1) % TESTIMONIALS.length);
    }, 4000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="min-h-screen bg-gradient-to-b from-rose-50 via-white to-pink-50 font-sans">
      
      {/* NAVIGATION */}
      <nav className="fixed top-0 w-full bg-white/90 backdrop-blur-xl border-b border-pink-200/50 z-50 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            
            <div className="flex items-center space-x-8">
              <div className="flex items-center space-x-3">
                <div className="w-12 h-12 bg-gradient-to-br from-pink-500 via-rose-500 to-purple-500 rounded-2xl flex items-center justify-center shadow-xl transform hover:scale-110 transition-transform">
                  <span className="text-white text-2xl">{CONFIG.brand.logo}</span>
                </div>
                <span className="font-black text-2xl bg-gradient-to-r from-pink-600 via-rose-600 to-purple-600 bg-clip-text text-transparent">
                  {CONFIG.brand.name}
                </span>
              </div>
              
              <div className="hidden md:flex items-center space-x-6">
                <a href="#fonctionnalites" className="text-slate-700 hover:text-pink-600 font-semibold transition-colors">Fonctionnalités</a>
                <a href="#tarifs" className="text-slate-700 hover:text-pink-600 font-semibold transition-colors">Tarifs</a>
                <a href="#temoignages" className="text-slate-700 hover:text-pink-600 font-semibold transition-colors">Témoignages</a>
                <a href="#faq" className="text-slate-700 hover:text-pink-600 font-semibold transition-colors">FAQ</a>
              </div>
            </div>

            <div className="hidden md:flex items-center space-x-4">
              <button 
                onClick={() => window.location.href = CONFIG.contact.loginUrl}
                className="px-5 py-2.5 text-slate-700 hover:text-pink-600 font-semibold transition-colors"
              >
                Connexion
              </button>
              <button 
                onClick={() => window.location.href = CONFIG.contact.signupUrl}
                className="px-6 py-3 bg-gradient-to-r from-pink-600 via-rose-600 to-purple-600 text-white rounded-xl font-bold hover:shadow-2xl hover:scale-105 transition-all"
              >
                Commencer 🚀
              </button>
            </div>

            <button 
              className="md:hidden p-2 rounded-lg hover:bg-pink-50"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            >
              {mobileMenuOpen ? <X className="w-6 h-6 text-pink-600" /> : <Menu className="w-6 h-6 text-pink-600" />}
            </button>
          </div>
        </div>

        {mobileMenuOpen && (
          <div className="md:hidden bg-white border-t border-pink-200 animate-fade-in">
            <div className="px-4 py-4 space-y-3">
              <a href="#fonctionnalites" className="block py-3 text-slate-700 hover:text-pink-600 font-semibold">Fonctionnalités</a>
              <a href="#tarifs" className="block py-3 text-slate-700 hover:text-pink-600 font-semibold">Tarifs</a>
              <a href="#temoignages" className="block py-3 text-slate-700 hover:text-pink-600 font-semibold">Témoignages</a>
              <a href="#faq" className="block py-3 text-slate-700 hover:text-pink-600 font-semibold">FAQ</a>
              <button 
                onClick={() => window.location.href = CONFIG.contact.signupUrl}
                className="w-full mt-4 px-6 py-3 bg-gradient-to-r from-pink-600 to-purple-600 text-white rounded-xl font-bold"
              >
                Commencer gratuitement
              </button>
            </div>
          </div>
        )}
      </nav>

      {/* HERO SECTION */}
      <section className="pt-32 pb-24 px-4 overflow-hidden relative">
        <div className="absolute inset-0 bg-gradient-to-br from-pink-100/50 via-rose-100/30 to-purple-100/50 -z-10"></div>
        
        <div className="max-w-7xl mx-auto text-center relative">
          
          <div className="inline-flex items-center space-x-2 px-5 py-2.5 bg-gradient-to-r from-pink-100 to-purple-100 rounded-full mb-8 border-2 border-pink-300 animate-fade-in-up shadow-lg">
            <span className="text-pink-700 font-bold text-sm">{CONFIG.hero.partnerBadge}</span>
          </div>

          <h1 className="text-5xl md:text-7xl lg:text-8xl font-black mb-6 leading-tight animate-fade-in-up" style={{ animationDelay: '0.1s' }}>
            <span className="bg-gradient-to-r from-pink-600 via-rose-600 to-purple-600 bg-clip-text text-transparent drop-shadow-lg">
              {CONFIG.hero.title}
            </span>
          </h1>

          <p className="text-2xl md:text-3xl text-slate-700 mb-4 font-bold animate-fade-in-up" style={{ animationDelay: '0.2s' }}>
            {CONFIG.hero.subtitle}
          </p>
          <p className="text-lg md:text-xl text-slate-600 mb-12 animate-fade-in-up" style={{ animationDelay: '0.3s' }}>
            {CONFIG.hero.tagline}
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-12 animate-fade-in-up" style={{ animationDelay: '0.4s' }}>
            <button 
              onClick={() => window.location.href = CONFIG.contact.signupUrl}
              className="px-10 py-5 bg-gradient-to-r from-pink-600 via-rose-600 to-purple-600 text-white text-xl rounded-2xl font-black hover:shadow-2xl hover:scale-110 transition-all flex items-center space-x-2"
            >
              <span>{CONFIG.hero.ctaButton}</span>
              <span className="text-2xl">🚀</span>
            </button>
            <button 
              onClick={() => window.location.href = CONFIG.contact.salesUrl}
              className="px-10 py-5 bg-white text-pink-600 text-xl rounded-2xl font-black hover:shadow-xl hover:scale-105 transition-all border-2 border-pink-600 flex items-center space-x-2"
            >
              <MessageCircle className="w-6 h-6" />
              <span>WhatsApp</span>
            </button>
          </div>

          <div className="mt-16 flex flex-wrap justify-center items-center gap-6 animate-fade-in-up" style={{ animationDelay: '0.5s' }}>
            {CONFIG.hero.partners.map((partner, index) => (
              <div key={index} className="px-6 py-3 bg-white rounded-xl shadow-lg border-2 border-pink-200 hover:scale-105 transition-transform">
                <span className={`font-bold text-${partner.color}`}>{partner.name}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* METHODES DE PAIEMENT */}
      <section className="py-12 px-4 bg-gradient-to-r from-pink-50 to-purple-50 border-y border-pink-200">
        <div className="max-w-7xl mx-auto">
          <p className="text-center text-slate-600 font-semibold mb-6">Acceptez tous les moyens de paiement africains :</p>
          <div className="flex flex-wrap justify-center items-center gap-6">
            {PAYMENT_METHODS.map((method, index) => (
              <div key={index} className="flex items-center space-x-2 px-5 py-3 bg-white rounded-lg shadow-md border border-pink-200 hover:scale-110 transition-transform">
                <span className="text-2xl">{method.icon}</span>
                <span className={`font-bold text-${method.color}`}>{method.name}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FONCTIONNALITES */}
      <section id="fonctionnalites" className="py-24 px-4 bg-white">
        <div className="max-w-7xl mx-auto">
          
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-6xl font-black mb-4 bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
              Simplifiez Vos Commandes WhatsApp
            </h2>
            <p className="text-xl text-slate-600 max-w-3xl mx-auto">
              Transformez votre numéro WhatsApp en boutique professionnelle en quelques minutes
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {FEATURES.map((feature, index) => (
              <div 
                key={index} 
                className={`bg-gradient-to-br ${feature.gradient} p-8 rounded-3xl shadow-xl border-2 border-${feature.color}-200 hover:shadow-2xl hover:-translate-y-3 transition-all group cursor-pointer`}
              >
                <div className="text-6xl mb-6 group-hover:scale-125 group-hover:rotate-6 transition-transform">
                  {feature.icon}
                </div>
                <h3 className={`text-2xl font-black mb-4 text-${feature.color}-900 group-hover:text-${feature.color}-600 transition-colors`}>
                  {feature.title}
                </h3>
                <p className="text-slate-700 leading-relaxed text-lg">
                  {feature.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* SHOWCASE WEBSITES */}
      <section className="py-24 px-4 bg-gradient-to-br from-pink-50 via-rose-50 to-purple-50">
        <div className="max-w-7xl mx-auto">
          <h2 className="text-4xl md:text-6xl font-black text-center mb-6 bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
            Un Site Web Magnifique
          </h2>
          <p className="text-xl text-slate-600 text-center mb-16 max-w-3xl mx-auto">
            Créez un site professionnel qui impressionne vos clients
          </p>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8 mb-12">
            {[
              { icon: "💄", label: "Catalogue Produits", color: "pink" },
              { icon: "🛒", label: "Panier d'Achat", color: "purple" },
              { icon: "💳", label: "Page de Paiement", color: "blue" },
              { icon: "📦", label: "Suivi Commandes", color: "green" },
              { icon: "⭐", label: "Avis Clients", color: "yellow" },
              { icon: "🎨", label: "Design Personnalisé", color: "rose" }
            ].map((item, index) => (
              <div 
                key={index} 
                className={`aspect-[3/4] bg-gradient-to-br from-${item.color}-200 to-${item.color}-300 rounded-3xl shadow-2xl hover:shadow-3xl hover:scale-105 transition-all overflow-hidden group border-4 border-${item.color}-400`}
              >
                <div className="w-full h-full flex items-center justify-center text-${item.color}-700 group-hover:text-${item.color}-900 transition-colors">
                  <div className="text-center p-8">
                    <div className="text-7xl mb-6 group-hover:scale-125 transition-transform">{item.icon}</div>
                    <p className="font-black text-xl">{item.label}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>

          <div className="grid md:grid-cols-2 gap-8">
            <div className="bg-white p-10 rounded-3xl shadow-2xl border-4 border-pink-300 hover:shadow-3xl transition-shadow">
              <div className="flex items-center space-x-4 mb-6">
                <div className="w-14 h-14 bg-gradient-to-br from-pink-500 to-purple-500 rounded-xl flex items-center justify-center">
                  <Zap className="w-8 h-8 text-white" />
                </div>
                <h3 className="text-3xl font-black text-slate-900">Nom de Domaine</h3>
              </div>
              <div className="text-pink-600 font-mono text-2xl bg-pink-50 px-6 py-4 rounded-xl border-2 border-pink-300 font-bold">
                maboutique.com
              </div>
              <p className="mt-4 text-slate-600">Votre propre adresse web professionnelle</p>
            </div>
            
            <div className="bg-white p-10 rounded-3xl shadow-2xl border-4 border-purple-300 hover:shadow-3xl transition-shadow">
              <div className="flex items-center space-x-4 mb-6">
                <div className="w-14 h-14 bg-gradient-to-br from-purple-500 to-pink-500 rounded-xl flex items-center justify-center">
                  <Star className="w-8 h-8 text-white" />
                </div>
                <h3 className="text-3xl font-black text-slate-900">Référencement SEO</h3>
              </div>
              <p className="text-slate-700 text-lg leading-relaxed">
                Optimisé pour Google, Bing et les moteurs de recherche. Vos clients vous trouvent facilement !
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* WHATSAPP BUSINESS API */}
      <section className="py-24 px-4 bg-white">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-6xl font-black mb-4 bg-gradient-to-r from-green-600 to-emerald-600 bg-clip-text text-transparent">
              Automatisation WhatsApp Business
            </h2>
            <p className="text-xl text-slate-600 max-w-3xl mx-auto">
              Envoyez des messages automatiques et boostez vos ventes
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {WHATSAPP_FEATURES.map((feature, index) => (
              <div key={index} className={`bg-gradient-to-br from-${feature.color}-50 to-${feature.color}-100 p-10 rounded-3xl border-4 border-${feature.color}-300 hover:shadow-2xl hover:scale-105 transition-all`}>
                <div className="text-6xl mb-6">{feature.icon}</div>
                <h3 className={`text-2xl font-black mb-4 text-${feature.color}-900`}>{feature.title}</h3>
                <p className="text-slate-700 text-lg leading-relaxed">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* TEMOIGNAGES */}
      <section id="temoignages" className="py-24 px-4 bg-gradient-to-b from-pink-50 to-white">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-6xl font-black mb-4 bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
              Ce Que Disent Nos Clients Africains
            </h2>
            <p className="text-xl text-slate-600">Des milliers d'entrepreneurs nous font confiance</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8 mb-12">
            {TESTIMONIALS.slice(0, 6).map((testimonial, index) => (
              <div 
                key={index}
                className="bg-white p-8 rounded-3xl shadow-2xl border-4 border-pink-200 hover:shadow-3xl hover:-translate-y-3 transition-all"
              >
                <div className="flex items-start space-x-4 mb-6">
                  <div className="w-20 h-20 bg-gradient-to-br from-pink-400 via-rose-400 to-purple-400 rounded-2xl flex items-center justify-center text-4xl shadow-xl">
                    {testimonial.avatar}
                  </div>
                  <div>
                    <h4 className="font-black text-xl text-slate-900">{testimonial.name}</h4>
                    <p className="text-sm font-semibold text-pink-600">{testimonial.company}</p>
                    <p className="text-xs text-slate-500">{testimonial.role}</p>
                  </div>
                </div>
                
                <div className="flex mb-4">
                  {[...Array(testimonial.rating)].map((_, i) => (
                    <Star key={i} className="w-6 h-6 fill-yellow-400 text-yellow-400" />
                  ))}
                </div>
                
                <p className="text-slate-700 text-lg font-medium leading-relaxed mb-4 italic">
                  "{testimonial.quote}"
                </p>
                
                <p className="text-sm font-semibold text-pink-600">{testimonial.country}</p>
              </div>
            ))}
          </div>

          <div className="text-center">
            <div className="inline-block px-8 py-4 bg-gradient-to-r from-pink-100 to-purple-100 rounded-2xl border-2 border-pink-300">
              <p className="text-2xl font-black text-pink-700">+ de 10 000 entrepreneurs satisfaits en Afrique 🌍</p>
            </div>
          </div>
        </div>
      </section>

      {/* PRICING */}
      <section id="tarifs" className="py-24 px-4 bg-gradient-to-br from-white via-pink-50 to-purple-50">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-6xl font-black mb-4 bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
              Tarifs Transparents
            </h2>
            <p className="text-xl text-slate-600">Prix adaptés au marché africain</p>
          </div>

          <div className="flex justify-center items-center space-x-4 mb-12">
            <span className={`font-bold text-lg ${!isAnnual ? 'text-pink-700' : 'text-slate-500'}`}>
              Mensuel
            </span>
            <button 
              onClick={() => setIsAnnual(!isAnnual)}
              className={`relative w-20 h-10 rounded-full transition-colors ${isAnnual ? 'bg-gradient-to-r from-pink-600 to-purple-600' : 'bg-slate-300'}`}
            >
              <div className={`absolute top-1 left-1 w-8 h-8 bg-white rounded-full shadow-lg transition-transform ${isAnnual ? 'translate-x-10' : ''}`} />
            </button>
            <span className={`font-bold text-lg ${isAnnual ? 'text-pink-700' : 'text-slate-500'}`}>
              Annuel <span className="text-green-600 font-black">(Économisez 25%)</span>
            </span>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {PRICING_PLANS.map((plan, index) => {
              const displayPrice = plan.monthlyPrice === null 
                ? "Sur Mesure" 
                : isAnnual 
                  ? plan.annualPrice 
                  : plan.monthlyPrice;

              return (
                <div 
                  key={index}
                  className={`bg-white rounded-3xl shadow-2xl overflow-hidden border-4 transition-all hover:shadow-3xl hover:-translate-y-3 ${
                    plan.highlighted ? 'border-pink-600 ring-8 ring-pink-200 scale-105' : 'border-pink-200'
                  }`}
                >
                  {plan.popularBadge && (
                    <div className="bg-gradient-to-r from-pink-600 via-rose-600 to-purple-600 text-white text-center py-3 font-black text-lg">
                      ⭐ PLUS POPULAIRE ⭐
                    </div>
                  )}
                  
                  <div className="p-10">
                    <h3 className="text-3xl font-black mb-4 text-slate-900">{plan.name}</h3>
                    
                    <div className="mb-6">
                      {typeof displayPrice === 'number' ? (
                        <>
                          <span className="text-6xl font-black bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
                            {displayPrice.toLocaleString()}
                          </span>
                          <span className="text-2xl font-bold text-slate-600 ml-2">{plan.currency}</span>
                          <p className="text-slate-500 font-semibold mt-2">par mois</p>
                        </>
                      ) : (
                        <span className="text-5xl font-black bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
                          {displayPrice}
                        </span>
                      )}
                    </div>

                    {plan.savings && isAnnual && (
                      <div className="mb-6 px-4 py-2 bg-green-100 border-2 border-green-300 rounded-xl">
                        <p className="text-green-700 font-black text-center">💰 {plan.savings}</p>
                      </div>
                    )}
                    
                    <p className="text-slate-600 mb-8 font-semibold text-lg">{plan.description}</p>
                    
                    <ul className="space-y-4 mb-10">
                      {plan.features.map((feature, featureIndex) => (
                        <li key={featureIndex} className="flex items-start space-x-3">
                          <div className="flex-shrink-0 w-6 h-6 bg-gradient-to-r from-green-500 to-emerald-500 rounded-full flex items-center justify-center mt-0.5">
                            <Check className="w-4 h-4 text-white font-bold" />
                          </div>
                          <span className="text-slate-700 font-medium text-lg">{feature}</span>
                        </li>
                      ))}
                    </ul>
                    
                    <button 
                      onClick={() => window.location.href = plan.name === "Entreprise" ? CONFIG.contact.salesUrl : CONFIG.contact.signupUrl}
                      className={`w-full py-4 rounded-2xl font-black text-lg transition-all ${
                        plan.highlighted 
                          ? 'bg-gradient-to-r from-pink-600 via-rose-600 to-purple-600 text-white hover:shadow-2xl hover:scale-105' 
                          : 'bg-gradient-to-r from-slate-100 to-slate-200 text-slate-900 hover:from-slate-200 hover:to-slate-300'
                      }`}
                    >
                      {plan.ctaText} →
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="text-center mt-12">
            <p className="text-slate-600 text-lg">
              ✅ Sans engagement • Annulez quand vous voulez • Remboursement 30 jours
            </p>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="py-24 px-4 bg-white">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-6xl font-black mb-4 bg-gradient-to-r from-pink-600 to-purple-600 bg-clip-text text-transparent">
              Questions Fréquentes
            </h2>
            <p className="text-xl text-slate-600">Tout ce que vous devez savoir</p>
          </div>

          <div className="space-y-6">
            {FAQ_ITEMS.map((faq, index) => (
              <details 
                key={index}
                className="bg-gradient-to-r from-pink-50 to-purple-50 rounded-2xl p-8 hover:from-pink-100 hover:to-purple-100 transition-colors group border-2 border-pink-200"
              >
                <summary className="font-black text-xl text-slate-900 cursor-pointer flex items-center justify-between">
                  <span>{faq.question}</span>
                  <ChevronDown className="w-6 h-6 text-pink-600 group-open:rotate-180 transition-transform flex-shrink-0 ml-4" />
                </summary>
                <p className="mt-6 text-slate-700 leading-relaxed text-lg pl-2 border-l-4 border-pink-400">
                  {faq.answer}
                </p>
              </details>
            ))}
          </div>

          <div className="mt-12 text-center p-8 bg-gradient-to-r from-pink-100 to-purple-100 rounded-3xl border-4 border-pink-300">
            <p className="text-2xl font-black text-slate-900 mb-4">D'autres questions ? 🤔</p>
            <button 
              onClick={() => window.location.href = CONFIG.contact.salesUrl}
              className="px-8 py-4 bg-gradient-to-r from-pink-600 to-purple-600 text-white rounded-xl font-black text-lg hover:shadow-2xl hover:scale-105 transition-all flex items-center space-x-2 mx-auto"
            >
              <MessageCircle className="w-6 h-6" />
              <span>Contactez-nous sur WhatsApp</span>
            </button>
          </div>
        </div>
      </section>

      {/* CTA FINALE */}
      <section className="py-24 px-4 bg-gradient-to-br from-pink-600 via-rose-600 to-purple-600 text-white relative overflow-hidden">
        <div className="absolute inset-0 bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNjAiIGhlaWdodD0iNjAiIHZpZXdCb3g9IjAgMCA2MCA2MCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48ZyBmaWxsPSJub25lIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjxwYXRoIGQ9Ik0zNiAxOGMzLjMxNCAwIDYgMi42ODYgNiA2cy0yLjY4NiA2LTYgNi02LTIuNjg2LTYtNiAyLjY4Ni02IDYtNnoiIHN0cm9rZT0iI0ZGRiIgc3Ryb2tlLW9wYWNpdHk9Ii4xIi8+PC9nPjwvc3ZnPg==')] opacity-20"></div>
        
        <div className="max-w-5xl mx-auto text-center relative z-10">
          <div className="inline-flex items-center space-x-2 px-6 py-3 bg-white/20 backdrop-blur-sm rounded-full mb-8 border-2 border-white/30">
            <span className="font-black text-lg">🌍 Solution 100% Africaine</span>
          </div>
          
          <h2 className="text-5xl md:text-7xl font-black mb-8 leading-tight drop-shadow-2xl">
            {CONFIG.brand.slogan}
          </h2>
          
          <p className="text-2xl md:text-3xl mb-12 font-semibold opacity-90">
            Rejoignez les 10 000+ entrepreneurs qui nous font confiance
          </p>
          
          <div className="flex flex-col sm:flex-row items-center justify-center gap-6">
            <button 
              onClick={() => window.location.href = CONFIG.contact.signupUrl}
              className="px-12 py-6 bg-white text-pink-600 text-2xl rounded-2xl font-black hover:shadow-2xl hover:scale-110 transition-all"
            >
              Commencer gratuitement 🚀
            </button>
            <button 
              onClick={() => window.location.href = CONFIG.contact.salesUrl}
              className="px-12 py-6 bg-transparent border-4 border-white text-white text-2xl rounded-2xl font-black hover:bg-white hover:text-pink-600 transition-all flex items-center space-x-3"
            >
              <Phone className="w-8 h-8" />
              <span>Appelez-nous</span>
            </button>
          </div>

          <p className="mt-8 text-lg opacity-75">
            ✅ Essai gratuit • Aucune carte bancaire requise • Support en français
          </p>
        </div>
      </section>

      {/* FOOTER */}
      <footer className="bg-slate-900 text-white py-16 px-4">
        <div className="max-w-7xl mx-auto">
          <div className="grid md:grid-cols-4 gap-10 mb-12">
            
            <div>
              <div className="flex items-center space-x-3 mb-6">
                <div className="w-12 h-12 bg-gradient-to-br from-pink-500 to-purple-500 rounded-xl flex items-center justify-center">
                  <span className="text-white text-2xl">{CONFIG.brand.logo}</span>
                </div>
                <span className="font-black text-2xl">{CONFIG.brand.name}</span>
              </div>
              <p className="text-slate-400 leading-relaxed mb-4">
                La solution africaine pour créer votre boutique WhatsApp en quelques minutes.
              </p>
              <div className="flex space-x-4">
                <a href="#" className="w-10 h-10 bg-slate-800 hover:bg-pink-600 rounded-lg flex items-center justify-center transition-colors">
                  <span>📘</span>
                </a>
                <a href="#" className="w-10 h-10 bg-slate-800 hover:bg-pink-600 rounded-lg flex items-center justify-center transition-colors">
                  <span>📷</span>
                </a>
                <a href="#" className="w-10 h-10 bg-slate-800 hover:bg-pink-600 rounded-lg flex items-center justify-center transition-colors">
                  <span>💼</span>
                </a>
              </div>
            </div>

            <div>
              <h3 className="font-black text-lg mb-6 text-pink-400">Fonctionnalités</h3>
              <ul className="space-y-3 text-slate-400">
                <li><a href="#" className="hover:text-white transition-colors">Commandes WhatsApp</a></li>
                <li><a href="#" className="hover:text-white transition-colors">API WhatsApp Business</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Paiements Mobile Money</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Chatbot Automatique</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Site Web Professionnel</a></li>
              </ul>
            </div>

            <div>
              <h3 className="font-black text-lg mb-6 text-pink-400">Ressources</h3>
              <ul className="space-y-3 text-slate-400">
                <li><a href="#" className="hover:text-white transition-colors">Centre d'Aide</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Guides Vidéo</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Blog</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Témoignages</a></li>
                <li><a href="#" className="hover:text-white transition-colors">Pays Disponibles</a></li>
              </ul>
            </div>

            <div>
              <h3 className="font-black text-lg mb-6 text-pink-400">Contact</h3>
              <ul className="space-y-4 text-slate-400">
                <li className="flex items-center space-x-2">
                  <Phone className="w-5 h-5 text-pink-400" />
                  <span>{CONFIG.contact.phone}</span>
                </li>
                <li className="flex items-center space-x-2">
                  <MessageCircle className="w-5 h-5 text-pink-400" />
                  <a href={CONFIG.contact.salesUrl} className="hover:text-white transition-colors">WhatsApp</a>
                </li>
                <li>
                  <a href="#" className="block px-6 py-3 bg-gradient-to-r from-pink-600 to-purple-600 rounded-xl hover:shadow-xl transition-all text-center font-bold mt-4">
                    📱 Télécharger l'App
                  </a>
                </li>
              </ul>
            </div>
          </div>

          <div className="border-t border-slate-800 pt-8 flex flex-col md:flex-row justify-between items-center gap-4 text-slate-400">
            <p>© 2026 {CONFIG.brand.name}. Tous droits réservés.</p>
            <div className="flex space-x-6">
              <a href="#" className="hover:text-white transition-colors">Politique de Confidentialité</a>
              <a href="#" className="hover:text-white transition-colors">Conditions d'Utilisation</a>
            </div>
          </div>
        </div>
      </footer>

      {/* STYLES */}
      <style jsx>{`
        @keyframes fade-in-up {
          from {
            opacity: 0;
            transform: translateY(30px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }

        @keyframes fade-in {
          from { opacity: 0; }
          to { opacity: 1; }
        }

        .animate-fade-in-up {
          animation: fade-in-up 0.8s ease-out forwards;
          opacity: 0;
        }

        .animate-fade-in {
          animation: fade-in 0.4s ease-out forwards;
        }

        @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800;900&display=swap');

        .font-sans {
          font-family: 'Poppins', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        }

        html {
          scroll-behavior: smooth;
        }

        details summary::-webkit-details-marker {
          display: none;
        }
      `}</style>
    </div>
  );
}
