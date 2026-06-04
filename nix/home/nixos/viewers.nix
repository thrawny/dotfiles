let
  imvDesktop = [ "imv.desktop" ];
  zathuraCbDesktop = [ "org.pwmt.zathura-cb.desktop" ];
  zathuraDjvuDesktop = [ "org.pwmt.zathura-djvu.desktop" ];
  zathuraPdfDesktop = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
  zathuraPsDesktop = [ "org.pwmt.zathura-ps.desktop" ];
in
{
  programs = {
    imv.enable = true;
    zathura.enable = true;
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "application/epub+zip" = zathuraPdfDesktop;
      "application/eps" = zathuraPsDesktop;
      "application/oxps" = zathuraPdfDesktop;
      "application/pdf" = zathuraPdfDesktop;
      "application/postscript" = zathuraPsDesktop;
      "application/x-cb7" = zathuraCbDesktop;
      "application/x-cbr" = zathuraCbDesktop;
      "application/x-cbt" = zathuraCbDesktop;
      "application/x-cbz" = zathuraCbDesktop;
      "application/x-eps" = zathuraPsDesktop;
      "application/x-fictionbook" = zathuraPdfDesktop;
      "application/x-mobipocket-ebook" = zathuraPdfDesktop;
      "image/eps" = zathuraPsDesktop;
      "image/vnd.djvu" = zathuraDjvuDesktop;
      "image/vnd.djvu+multipage" = zathuraDjvuDesktop;
      "image/x-eps" = zathuraPsDesktop;

      "image/avif" = imvDesktop;
      "image/bmp" = imvDesktop;
      "image/gif" = imvDesktop;
      "image/heif" = imvDesktop;
      "image/jpeg" = imvDesktop;
      "image/jpg" = imvDesktop;
      "image/jxl" = imvDesktop;
      "image/png" = imvDesktop;
      "image/qoi" = imvDesktop;
      "image/svg+xml" = imvDesktop;
      "image/tiff" = imvDesktop;
      "image/webp" = imvDesktop;
      "image/x-bmp" = imvDesktop;
      "image/x-farbfeld" = imvDesktop;
      "image/x-png" = imvDesktop;
    };
  };
}
