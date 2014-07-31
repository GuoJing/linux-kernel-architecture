cafe:
	jekyll build
	ghp-import _site -b gitcafe-pages -r cafe -p

linux:
	jekyll build
	ghp-import _site -b gh-pages -r linux -p

pub:
	make cafe
	make linux
