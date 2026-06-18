import Navbar from './components/rh/Navbar'
import Hero from './components/rh/Hero'
import Overview from './components/rh/Overview'
import FloorPlans from './components/rh/FloorPlans'
import Exterior from './components/rh/Exterior'
import Interior from './components/rh/Interior'
import Specifications from './components/rh/Specifications'
import Materials from './components/rh/Materials'
import Gallery from './components/rh/Gallery'
import Contact from './components/rh/Contact'
import Footer from './components/rh/Footer'

export default function App() {
  return (
    <div className="min-h-screen bg-black text-white tracking-luxe">
      <Navbar />
      <main>
        <Hero />
        <Overview />
        <FloorPlans />
        <Exterior />
        <Interior />
        <Specifications />
        <Materials />
        <Gallery />
        <Contact />
      </main>
      <Footer />
    </div>
  )
}
