import * as THREE from 'three';
import { STLLoader } from 'three/examples/jsm/loaders/STLLoader.js'

const width  = 128;
const height = 128;
const renderer = new THREE.WebGLRenderer({ antialias: true });
async function renderSTLToImage(stlUrl) {
    return new Promise((resolve, reject) => {
      const scene = new THREE.Scene();
      const camera = new THREE.OrthographicCamera(
        -width * .28, width * .28, height * .28, -height * .28, 0.1, 1000
      );
      renderer.setSize(width, height);
      renderer.setClearColor(0xffffff, 1); // white background
  
      const light = new THREE.HemisphereLight(0xffffff, 0x444444);
      scene.add(light);
  
      const loader = new STLLoader();
      loader.load(stlUrl, geometry => {
        const material = new THREE.MeshStandardMaterial({ color: 0x008b8b }); // DarkCyan
        const mesh = new THREE.Mesh(geometry, material);
        mesh.rotation.x = -Math.PI / 2; // Rotate 90 degrees around the Y axis
        scene.add(mesh);
  
        // Center and scale
        const box = new THREE.Box3().setFromObject(mesh);
        const center = box.getCenter(new THREE.Vector3());
        const size = box.getSize(new THREE.Vector3());
        mesh.position.sub(center);
        const maxDim = Math.max(size.x, size.y, size.z);
        camera.zoom = Math.min(width / maxDim, height / maxDim) * 0.4; // Adjust zoom to fit
        camera.updateProjectionMatrix(); // Ensure the camera updates its projection
        camera.position.set(size.x, size.y * 2, size.z * 2); // Position the camera to view the object
        camera.lookAt(0, 0, 0);
  
        renderer.render(scene, camera);
  
        // ✅ Get base64 image
        const dataUrl = renderer.domElement.toDataURL("image/png");
  
        // Clean up
        geometry.dispose();
        material.dispose();
        renderer.dispose();
  
        resolve(dataUrl); // return base64 image
      }, undefined, err => reject(err));
    });
  }

document.addEventListener("DOMContentLoaded", () => {
    // setInterval(() => {
        const links = Array.from(document.querySelectorAll('a[href$=".stl"]')).filter(link => !link.querySelector('img'));
        links.forEach((link, index) => {
          const file   = link.getAttribute("href");
    
          renderSTLToImage(file).then(dataUrl => {
            const img = document.createElement('img');
            img.src = dataUrl;
            img.style.width = `${width}px`;
            link.innerHTML = "";
            link.appendChild(img);
          });
        });
    // }, 1000);
  });
  