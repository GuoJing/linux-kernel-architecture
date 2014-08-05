cafe:
	jekyll build
	ghp-import _site -b gitcafe-pages -r cafe -p

linux:
	jekyll build
	ghp-import _site -p -n

pub:
	make cafe
	make linux
	git ci -am'auto commit'
	git push origin master
